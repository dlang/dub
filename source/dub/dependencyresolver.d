/**
	Dependency configuration/version resolution algorithm.

	Copyright: © 2014-2018 Sönke Ludwig
	License: Subject to the terms of the MIT license, as written in the included LICENSE.txt file.
	Authors: Sönke Ludwig
*/
module dub.dependencyresolver;

import dub.dependency;
import dub.internal.vibecompat.core.log;

import std.algorithm;
import std.array : appender, array, join;
import std.conv : to;
import std.exception : enforce;
import std.range;
import std.typecons : Nullable;
import std.string;


/** Resolves dependency graph with multiple configurations per package.

	The term "configuration" can mean any kind of alternative dependency
	configuration of a package. In particular, it can mean different
	versions of a package.
*/
class DependencyResolver {
	/** Encapsulates a list of outgoing edges in the dependency graph.

		A value of this type represents a single dependency with multiple
		possible configurations for the target package.
	*/
	static struct TreeNodes {
		string pack;
		Dependency dependency;
		DependencyType depType = DependencyType.required;
	}

	/** A single node in the dependency graph.

		Nodes are a combination of a package and a single package configuration.
	*/
	static struct TreeNode {
		string pack;
		Dependency config;
		invariant (config.isExactVersion);
	}

	Dependency[string] resolve(TreeNode root, bool throw_on_failure = true)
	{
		// Leave the possibility to opt-out from the loop limit
		import std.process : environment;
		bool no_loop_limit = environment.get("DUB_NO_RESOLVE_LIMIT") !is null;

		auto rootbase = root.pack.basePackageName;

		// build up the dependency graph, eliminating as many configurations/
		// versions as possible
		ResolveContext context;
		context.configs[rootbase] = [ResolveConfig(root.config, true)];
		long loop_counter = no_loop_limit ? long.max : 1_000_000;
		constrain(root, context, loop_counter);

		// remove any non-default optional dependencies
		purgeOptionalDependencies(root, context.result);

		// the root package is implied by the `root` argument and will not be
		// returned explicitly
		context.result.remove(rootbase);

		logDiagnostic("Dependency resolution result:");
		foreach (d; context.result.keys.sort())
			logDiagnostic("  %s: %s", d, context.result[d]);

		return context.result;
	}

	protected abstract Dependency[] getAllConfigs(string pack);
	protected abstract Dependency[] getSpecificConfigs(string pack, TreeNodes nodes);
	protected abstract TreeNodes[] getChildren(TreeNode node);
	protected abstract bool matches(Dependency configs, Dependency config);

	private static struct ResolveConfig {
		Dependency config;
		bool included;
	}

	private static struct ResolveContext {
		/** Contains all packages visited by the resolution process so far.

			The key is the qualified name of the package (base + sub)
		*/
		void[0][string] visited;

		/// The finally chosen configurations for each package
		Dependency[string] result;

		/// The set of available configurations for each package
		ResolveConfig[][string] configs;

		/// Determines if a certain package has already been processed
		bool isVisited(string package_) const { return (package_ in visited) !is null; }

		/// Marks a package as processed
		void setVisited(string package_) { visited[package_] = (void[0]).init; }

		/// Returns a deep clone
		ResolveContext clone()
		{
			ResolveContext ret;
			ret.visited = this.visited.dup;
			ret.result = this.result.dup;
			foreach (pack, cfgs; this.configs) {
				ret.configs[pack] = cfgs.dup;
			}
			return ret;
		}
	}


	/** Starting with a single node, fills `context` with a minimized set of
		configurations that form valid solutions.
	*/
	private void constrain(TreeNode n, ref ResolveContext context, ref long max_iterations)
	{
		auto base = n.pack.basePackageName;
		assert(base in context.configs);
		if (context.isVisited(n.pack)) return;
		context.setVisited(n.pack);
		context.result[base] = n.config;
		foreach (j, ref sc; context.configs[base])
			sc.included = sc.config == n.config;

		auto dependencies = getChildren(n);

		foreach (dep; dependencies) {
			// lazily load all dependency configurations
			auto depbase = dep.pack.basePackageName;
			auto di = depbase in context.configs;
			if (!di) {
				context.configs[depbase] =
					getAllConfigs(depbase)
					.map!(c => ResolveConfig(c, true))
					.array;
				di = depbase in context.configs;
			}

			// add any dependee defined dependency configurations
			foreach (sc; getSpecificConfigs(n.pack, dep))
				if (!(*di).canFind!(c => c.config == sc))
					*di = ResolveConfig(sc, true) ~ *di;

			// restrain the configurations to the current dependency spec
			bool any_config = false;
			foreach (i, ref c; *di)
				if (c.included) {
					if (!matches(dep.dependency, c.config))
						c.included = false;
					else any_config = true;
				}

			if (!any_config && dep.depType == DependencyType.required) {
				if ((*di).length)
					throw new ResolveException(n, dep, context);
				else throw new DependencyLoadException(n, dep);
			}
		}

		constrainDependencies(n, dependencies, 0, context, max_iterations);
	}

	/** Recurses back into `constrain` while recursively going through `n`'s
		dependencies.

		This attempts to constrain each dependency, while keeping each of them
		in a nested stack frame. This allows any errors to properly back
		propagate.
	*/
	private void constrainDependencies(TreeNode n, TreeNodes[] dependencies, size_t depidx,
		ref ResolveContext context, ref long max_iterations)
	{
		if (depidx >= dependencies.length) return;

		assert (--max_iterations > 0,
			"The dependency resolution process is taking too long. The"
			~ " dependency graph is likely hitting a pathological case in"
			~ " the resolution algorithm. Please file a bug report at"
			~ " https://github.com/dlang/dub/issues and mention the package"
			~ " recipe that reproduces this error.");

		auto dep = &dependencies[depidx];
		auto depbase = dep.pack.basePackageName;
		auto depconfigs = context.configs[depbase];

		Exception first_err;

		// try each configuration/version of the current dependency
		foreach (i, c; depconfigs) {
			if (c.included) {
				try {
					// try the configuration on a cloned context
					auto subcontext = context.clone;
					constrain(TreeNode(dep.pack, c.config), subcontext, max_iterations);
					constrainDependencies(n, dependencies, depidx+1, subcontext, max_iterations);
					// if a branch succeeded, replace the current context
					// with the one from the branch and return
					context = subcontext;
					return;
				} catch (Exception e) {
					if (!first_err) first_err = e;
				}
			}
		}

		// ignore unsatisfiable optional dependencies
		if (dep.depType != DependencyType.required) {
			auto subcontext = context.clone;
			constrainDependencies(n, dependencies, depidx+1, subcontext, max_iterations);
			context = subcontext;
			return;
		}

		// report the first error encountered to the user
		if (first_err) throw first_err;

		// should have thrown in constrainRec before reaching this
		assert(false, format("Got no configuration for dependency %s %s of %s %s!?",
			dep.pack, dep.dependency, n.pack, n.config));
	}

	private void purgeOptionalDependencies(TreeNode root, ref Dependency[string] configs)
	{
		bool[string] required;
		bool[string] visited;

		void markRecursively(TreeNode node)
		{
			if (node.pack in visited) return;
			visited[node.pack] = true;
			required[node.pack.basePackageName] = true;
			foreach (dep; getChildren(node).filter!(dep => dep.depType != DependencyType.optional))
				if (auto dp = dep.pack.basePackageName in configs)
					markRecursively(TreeNode(dep.pack, *dp));
		}

		// recursively mark all required dependencies of the concrete dependency tree
		markRecursively(root);

		// remove all un-marked configurations
		foreach (p; configs.keys.dup)
			if (p !in required)
				configs.remove(p);
	}

	final class ResolveException : Exception {
		import std.range : chain, only;
		import std.typecons : tuple;

		string failedNode;

		this(TreeNode parent, TreeNodes dep, in ref ResolveContext context, string file = __FILE__, size_t line = __LINE__)
		{
			auto m = format("Unresolvable dependencies to package %s:", dep.pack.basePackageName);
			super(m, file, line);

			this.failedNode = dep.pack;

			auto failbase = failedNode.basePackageName;

			// get the list of all dependencies to the failed package
			auto deps = context.visited.byKey
				.filter!(p => p.basePackageName in context.result)
				.map!(p => TreeNode(p, context.result[p.basePackageName]))
				.map!(n => getChildren(n)
					.filter!(d => d.pack.basePackageName == failbase)
					.map!(d => tuple(n, d))
				)
				.join
				.sort!((a, b) => a[0].pack < b[0].pack);

			foreach (d; deps) {
				// filter out trivial self-dependencies
				if (d[0].pack.basePackageName == failbase
					&& matches(d[1].dependency, d[0].config))
					continue;
				msg ~= format("\n  %s %s depends on %s %s", d[0].pack, d[0].config, d[1].pack, d[1].dependency);
			}
		}
	}

	final class DependencyLoadException : Exception {
		TreeNode parent;
		TreeNodes dependency;

		this(TreeNode parent, TreeNodes dep)
		{
			auto m = format("Failed to find any versions for package %s, referenced by %s %s",
				dep.pack, parent.pack, parent.config);
			super(m, file, line);

			this.parent = parent;
			this.dependency = dep;
		}
	}
}

enum DependencyType {
	required,
	optionalDefault,
	optional
}

private string basePackageName(string p)
{
	import std.algorithm.searching : findSplit;
	return p.findSplit(":")[0];
}

unittest {
	// properly back up if conflicts are detected along the way (d:2 vs d:1)
	with (TestResolver) {
		auto res = new TestResolver([
			"a:0.0.0": [
				TreeNodes("b", Dependency(">=1.0.0 <=2.0.0")),
				TreeNodes("d", Dependency("1.0.0")),
				TreeNodes("e", Dependency(">=1.0.0 <=2.0.0")),
			],
			"b:1.0.0": [
				TreeNodes("c", Dependency(">=1.0.0 <=2.0.0")),
				TreeNodes("d", Dependency("1.0.0")),
			],
			"b:2.0.0": [
				TreeNodes("c", Dependency(">=2.0.0 <=3.0.0")),
				TreeNodes("d", Dependency(">=1.0.0 <=2.0.0")),
			],
			"c:1.0.0": [], "c:2.0.0": [], "c:3.0.0": [],
			"d:1.0.0": [], "d:2.0.0": [],
			"e:1.0.0": [], "e:2.0.0": [],
		]);
		assert(res.resolve(TreeNode("a", Dependency("0.0.0"))) == [
				"b":Dependency("2.0.0"),
				"c":Dependency("3.0.0"),
				"d":Dependency("1.0.0"),
				"e":Dependency("2.0.0")
			], format("%s", res.resolve(TreeNode("a", Dependency("0.0.0")))));
	}
}

unittest {
	// handle cyclic dependencies gracefully
	with (TestResolver) {
		auto res = new TestResolver([
			"a:0.0.0": [TreeNodes("b", Dependency("1.0.0"))],
			"b:1.0.0": [TreeNodes("b", Dependency("1.0.0"))],
		]);
		assert(res.resolve(TreeNode("a", Dependency("0.0.0"))) == ["b":Dependency("1.0.0")]);
	}
}

unittest {
	// don't choose optional dependencies by default
	with (TestResolver) {
		auto res = new TestResolver([
			"a:0.0.0": [TreeNodes("b", Dependency("1.0.0"), DependencyType.optional)],
			"b:1.0.0": []
		]);
		assert(
			res.resolve(TreeNode("a", Dependency("0.0.0"))).empty,
			res.resolve(TreeNode("a", Dependency("0.0.0"))).to!string);
	}
}

unittest {
	// choose default optional dependencies by default
	with (TestResolver) {
		auto res = new TestResolver([
			"a:0.0.0": [TreeNodes("b", Dependency("1.0.0"), DependencyType.optionalDefault)],
			"b:1.0.0": []
		]);
		assert(
			res.resolve(TreeNode("a", Dependency("0.0.0"))) == ["b":Dependency("1.0.0")],
			res.resolve(TreeNode("a", Dependency("0.0.0"))).to!string);
	}
}

unittest {
	// choose optional dependency if non-optional within the dependency tree
	with (TestResolver) {
		auto res = new TestResolver([
			"a:0.0.0": [
				TreeNodes("b", Dependency("1.0.0"), DependencyType.optional),
				TreeNodes("c", Dependency("1.0.0")),
			],
			"b:1.0.0": [],
			"c:1.0.0": [TreeNodes("b", Dependency("1.0.0"))],
		]);
		assert(
			res.resolve(TreeNode("a", Dependency("0.0.0"))) == ["b":Dependency("1.0.0"), "c":Dependency("1.0.0")],
			res.resolve(TreeNode("a", Dependency("0.0.0"))).to!string);
	}
}

unittest {
	// don't choose optional dependency if non-optional outside of final dependency tree
	with (TestResolver) {
		auto res = new TestResolver([
			"a:0.0.0": [TreeNodes("b", Dependency("1.0.0"), DependencyType.optional)],
			"b:1.0.0": [],
			"preset:0.0.0": [TreeNodes("b", Dependency("1.0.0"))]
		]);
		assert(
			res.resolve(TreeNode("a", Dependency("0.0.0"))).empty,
			res.resolve(TreeNode("a", Dependency("0.0.0"))).to!string);
	}
}

unittest {
	// don't choose optional dependency if non-optional in a non-selected version
	with (TestResolver) {
		auto res = new TestResolver([
			"a:0.0.0": [TreeNodes("b", Dependency(">=1.0.0 <=2.0.0"))],
			"b:1.0.0": [TreeNodes("c", Dependency("1.0.0"))],
			"b:2.0.0": [TreeNodes("c", Dependency("1.0.0"), DependencyType.optional)],
			"c:1.0.0": []
		]);
		assert(res.resolve(TreeNode("a", Dependency("0.0.0"))) == ["b":Dependency("2.0.0")], to!string(res.resolve(TreeNode("a", Dependency("0.0.0")))));
	}
}

unittest {
	// make sure non-satisfiable dependencies are not a problem, even if non-optional in some dependencies
	with (TestResolver) {
		auto res = new TestResolver([
			"a:0.0.0": [TreeNodes("b", Dependency(">=1.0.0 <=2.0.0"))],
			"b:1.0.0": [TreeNodes("c", Dependency("2.0.0"))],
			"b:2.0.0": [TreeNodes("c", Dependency("2.0.0"), DependencyType.optional)],
			"c:1.0.0": []
		]);
		assert(res.resolve(TreeNode("a", Dependency("0.0.0"))) == ["b":Dependency("2.0.0")], to!string(res.resolve(TreeNode("a", Dependency("0.0.0")))));
	}
}

unittest {
	// check error message for multiple conflicting dependencies
	with (TestResolver) {
		auto res = new TestResolver([
			"a:0.0.0": [TreeNodes("b", Dependency("1.0.0")), TreeNodes("c", Dependency("1.0.0"))],
			"b:1.0.0": [TreeNodes("d", Dependency("1.0.0"))],
			"c:1.0.0": [TreeNodes("d", Dependency("2.0.0"))],
			"d:1.0.0": [],
			"d:2.0.0": []
		]);
		try {
			res.resolve(TreeNode("a", Dependency("0.0.0")));
			assert(false, "Expected resolve to throw.");
		} catch (ResolveException e) {
			assert(e.msg ==
				"Unresolvable dependencies to package d:"
				~ "\n  b 1.0.0 depends on d 1.0.0"
				~ "\n  c 1.0.0 depends on d 2.0.0");
		}
	}
}

unittest {
	// check error message for invalid dependency
	with (TestResolver) {
		auto res = new TestResolver([
			"a:0.0.0": [TreeNodes("b", Dependency("1.0.0"))]
		]);
		try {
			res.resolve(TreeNode("a", Dependency("0.0.0")));
			assert(false, "Expected resolve to throw.");
		} catch (DependencyLoadException e) {
			assert(e.msg == "Failed to find any versions for package b, referenced by a 0.0.0");
		}
	}

	// regression: unresolvable optional dependency skips the remaining dependencies
	with (TestResolver) {
		auto res = new TestResolver([
			"a:0.0.0": [
				TreeNodes("b", Dependency("2.0.0"), DependencyType.optional),
				TreeNodes("c", Dependency("1.0.0"))
			],
			"b:1.0.0": [],
			"c:1.0.0": []
		]);
		assert(res.resolve(TreeNode("a", Dependency("0.0.0"))) == ["c":Dependency("1.0.0")]);
	}
}

private class TestResolver : DependencyResolver {
	private TreeNodes[][string] m_children;
	this(TreeNodes[][string] children) { m_children = children; }
	protected override Dependency[] getAllConfigs(string pack) {
		auto ret = appender!(Dependency[]);
		foreach (p; m_children.byKey) {
			if (p.length <= pack.length+1) continue;
			if (p[0 .. pack.length] != pack || p[pack.length] != ':') continue;
			ret ~= Dependency(p.find(':').dropOne);
		}
		ret.data.sort!"a>b"();
		return ret.data;
	}
	protected override Dependency[] getSpecificConfigs(string pack, TreeNodes nodes) { return null; }
	protected override TreeNodes[] getChildren(TreeNode node) { return m_children.get(node.pack ~ ":" ~ node.config.to!string(), null); }
	protected override bool matches(Dependency configs, Dependency config) { return configs.merge(config).valid; }
}
