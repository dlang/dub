/**
	Dependency configuration/version resolution algorithm.

	Copyright: © 2014-2018 Sönke Ludwig
	License: Subject to the terms of the MIT license, as written in the included LICENSE.txt file.
	Authors: Sönke Ludwig
*/
module dub.dependencyresolver;

import dub.dependency;
import dub.internal.vibecompat.core.log;

import std.algorithm : all, canFind, filter, map, sort;
import std.array : appender, array, join;
import std.conv : to;
import std.exception : enforce;
import std.string : format, lastIndexOf;


/** Resolves dependency graph with multiple configurations per package.

	The term "configuration" can mean any kind of alternative dependency
	configuration of a package. In particular, it can mean different
	versions of a package.

	`CONFIG` is an abstract type denoting a single configuration of a certain
	package, whereas `CONFIGS` denotes a set of configurations. The
	representation of both can be freely chosen, so that `CONFIGS` for example
	can be defined in terms of a version range.
*/
class DependencyResolver(CONFIGS, CONFIG) {
	/** Encapsulates a list of outgoing edges in the dependency graph.

		A value of this type represents a single dependency with multiple
		possible configurations for the target package.
	*/
	static struct TreeNodes {
		PackageId package_id;
		CONFIGS configs;
		DependencyType depType = DependencyType.required;

		size_t toHash() const nothrow @trusted {
			size_t ret = typeid(PackageId).getHash(&package_id);
			ret ^= typeid(CONFIGS).getHash(&configs);
			return ret;
		}
		bool opEqual(const scope ref TreeNodes other) const { return package_id == other.package_id && configs == other.configs; }
		int opCmp(const scope ref TreeNodes other) const {
			if (package_id != other.package_id) return package_id < other.package_id ? -1 : 1;
			if (configs != other.configs) return configs < other.configs ? -1 : 1;
			return 0;
		}
	}

	/** A single node in the dependency graph.

		Nodes are a combination of a package and a single package configuration.
	*/
	static struct TreeNode {
		PackageId package_id;
		CONFIG config;

		size_t toHash() const nothrow @trusted {
			size_t ret = package_id.hashOf();
			ret ^= typeid(CONFIG).getHash(&config);
			return ret;
		}
		bool opEqual(const scope ref TreeNode other) const { return package_id == other.package_id && config == other.config; }
		int opCmp(const scope ref TreeNode other) const {
			if (package_id != other.package_id) return package_id < other.package_id ? -1 : 1;
			if (config != other.config) return config < other.config ? -1 : 1;
			return 0;
		}
	}

	CONFIG[PackageId] resolve(TreeNode root, bool throw_on_failure = true)
	{
		// Leave the possibility to opt-out from the loop limit
		import std.process : environment;
		bool no_loop_limit = environment.get("DUB_NO_RESOLVE_LIMIT") !is null;

		const rootbase = basePackageName(root.package_id);

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

	protected abstract CONFIG[] getAllConfigs(PackageId package_id);
	protected abstract CONFIG[] getSpecificConfigs(PackageId package_id, TreeNodes nodes);
	protected abstract TreeNodes[] getChildren(TreeNode node);
	protected abstract bool matches(CONFIGS configs, CONFIG config);

	private static struct ResolveConfig {
		CONFIG config;
		bool included;
	}

	private static struct ResolveContext {
		/** Contains all packages visited by the resolution process so far.

			The key is the qualified name of the package (base + sub)
		*/
		void[0][PackageId] visited;

		/// The finally chosen configurations for each package
		CONFIG[PackageId] result;

		/// The set of available configurations for each package
		ResolveConfig[][PackageId] configs;

		/// Determines if a certain package has already been processed
		bool isVisited(PackageId package_id) const { return (package_id in visited) !is null; }

		/// Marks a package as processed
		void setVisited(PackageId package_id) { visited[package_id] = (void[0]).init; }

		/// Returns a deep clone
		ResolveContext clone()
		{
			ResolveContext ret;
			ret.visited = this.visited.dup;
			ret.result = this.result.dup;
			foreach (package_id, cfgs; this.configs) {
				ret.configs[package_id] = cfgs.dup;
			}
			return ret;
		}
	}


	/** Starting with a single node, fills `context` with a minimized set of
		configurations that form valid solutions.
	*/
	private void constrain(TreeNode n, ref ResolveContext context, ref long max_iterations)
	{
		PackageId base = n.package_id.basePackageName;
		assert(base in context.configs);
		if (context.isVisited(n.package_id)) return;
		context.setVisited(n.package_id);
		context.result[base] = n.config;
		foreach (j, ref sc; context.configs[base])
			sc.included = sc.config == n.config;

		auto dependencies = getChildren(n);

		foreach (dep; dependencies) {
			// lazily load all dependency configurations
			auto depbase = basePackageName(dep.package_id);
			auto di = depbase in context.configs;
			if (!di) {
				context.configs[depbase] =
					getAllConfigs(depbase)
					.map!(c => ResolveConfig(c, true))
					.array;
				di = depbase in context.configs;
			}

			// add any dependee defined dependency configurations
			foreach (sc; getSpecificConfigs(n.package_id, dep))
				if (!(*di).canFind!(c => c.config == sc))
					*di = ResolveConfig(sc, true) ~ *di;

			// restrain the configurations to the current dependency spec
			bool any_config = false;
			foreach (i, ref c; *di)
				if (c.included) {
					if (!matches(dep.configs, c.config))
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
		auto depbase = dep.package_id.basePackageName;
		auto depconfigs = context.configs[depbase];

		Exception first_err;

		// try each configuration/version of the current dependency
		foreach (i, c; depconfigs) {
			if (c.included) {
				try {
					// try the configuration on a cloned context
					auto subcontext = context.clone;
					constrain(TreeNode(dep.package_id, c.config), subcontext, max_iterations);
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
			dep.package_id, dep.configs, n.package_id, n.config));
	}

	private void purgeOptionalDependencies(TreeNode root, ref CONFIG[PackageId] configs)
	{
		bool[PackageId] required;
		bool[PackageId] visited;

		void markRecursively(TreeNode node)
		{
			if (node.package_id in visited) return;
			visited[node.package_id] = true;
			required[node.package_id.basePackageName] = true;
			foreach (dep; getChildren(node).filter!(dep => dep.depType != DependencyType.optional))
				if (auto dp = dep.package_id.basePackageName in configs)
					markRecursively(TreeNode(dep.package_id, *dp));
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

		PackageId failedNode;

		this(TreeNode parent, TreeNodes dep, const scope ref ResolveContext context, string file = __FILE__, size_t line = __LINE__)
		{
			auto m = format("Unresolvable dependencies to package %s:", dep.package_id.basePackageName);
			super(m, file, line);

			this.failedNode = dep.package_id;

			auto failbase = basePackageName(failedNode);

			// get the list of all dependencies to the failed package
			auto deps = context.visited.byKey
				.filter!(p => p.basePackageName in context.result)
				.map!(p => TreeNode(p, context.result[p.basePackageName]))
				.map!(n => getChildren(n)
					.filter!(d => d.package_id.basePackageName == failbase)
					.map!(d => tuple(n, d))
				)
				.join
				.sort!((a, b) => a[0].package_id < b[0].package_id);

			foreach (d; deps) {
				// filter out trivial self-dependencies
				if (d[0].package_id.basePackageName == failbase
					&& matches(d[1].configs, d[0].config))
					continue;
				msg ~= format("\n  %s %s depends on %s %s", d[0].package_id, d[0].config, d[1].package_id, d[1].configs);
			}
		}
	}

	final class DependencyLoadException : Exception {
		TreeNode parent;
		TreeNodes dependency;

		this(TreeNode parent, TreeNodes dep)
		{
			auto m = format("Failed to find any versions for package %s, referenced by %s %s",
				dep.package_id, parent.package_id, parent.config);
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

private PackageId basePackageName(PackageId p)
{
	import std.algorithm.searching : findSplit;
	return typeof(return)(p._pn.findSplit(":")[0]);
}

unittest {
	static struct IntConfig {
		int value;
		alias value this;
		enum invalid = IntConfig(-1);
	}
	static IntConfig ic(int v) { return IntConfig(v); }
	static struct IntConfigs {
		IntConfig[] configs;
		alias configs this;
	}
	static IntConfigs ics(IntConfig[] cfgs) { return IntConfigs(cfgs); }

	static class TestResolver : DependencyResolver!(IntConfigs, IntConfig) {
		private TreeNodes[][string] m_children;
		this(TreeNodes[][string] children) { m_children = children; }
		protected override IntConfig[] getAllConfigs(PackageId package_id) {
			auto ret = appender!(IntConfig[]);
			foreach (p; m_children.byKey) {
				if (p.length <= package_id.length+1) continue;
				if (p[0 .. package_id.length] != package_id || p[package_id.length] != ':') continue;
				auto didx = p.lastIndexOf(':');
				ret ~= ic(p[didx+1 .. $].to!uint);
			}
			ret.data.sort!"a>b"();
			return ret.data;
		}
		protected override IntConfig[] getSpecificConfigs(PackageId package_id, TreeNodes nodes) { return null; }
		protected override TreeNodes[] getChildren(TreeNode node) { return m_children.get(node.package_id ~ ":" ~ node.config.to!string(), null); }
		protected override bool matches(IntConfigs configs, IntConfig config) { return configs.canFind(config); }
	}

	alias P = PackageId;

	// properly back up if conflicts are detected along the way (d:2 vs d:1)
	with (TestResolver) {
		auto res = new TestResolver([
										P("a:0"): [TreeNodes(P("b"), ics([ic(2), ic(1)])), TreeNodes(P("d"), ics([ic(1)])), TreeNodes(P("e"), ics([ic(2), ic(1)]))],
										P("b:1"): [TreeNodes(P("c"), ics([ic(2), ic(1)])), TreeNodes(P("d"), ics([ic(1)]))],
										P("b:2"): [TreeNodes(P("c"), ics([ic(3), ic(2)])), TreeNodes(P("d"), ics([ic(2), ic(1)]))],
										P("c:1"): [], P("c:2"): [], P("c:3"): [],
										P("d:1"): [], P("d:2"): [],
										P("e:1"): [], P("e:2"): [],
		]);
		assert(res.resolve(TreeNode(P("a"), ic(0))) == [P("b"):ic(2), P("c"):ic(3), P("d"):ic(1), P("e"):ic(2)], format(P("%s"), res.resolve(TreeNode(P("a"), ic(0)))));
	}

	// handle cyclic dependencies gracefully
	with (TestResolver) {
		auto res = new TestResolver([
										P("a:0"): [TreeNodes(P("b"), ics([ic(1)]))],
										P("b:1"): [TreeNodes(P("b"), ics([ic(1)]))]
		]);
		assert(res.resolve(TreeNode(P("a"), ic(0))) == [P("b"):ic(1)]);
	}

	// don't choose optional dependencies by default
	with (TestResolver) {
		auto res = new TestResolver([
										P("a:0"): [TreeNodes(P("b"), ics([ic(1)]), DependencyType.optional)],
										P("b:1"): []
		]);
		assert(res.resolve(TreeNode(P("a"), ic(0))).length == 0, to!string(res.resolve(TreeNode(P("a"), ic(0)))));
	}

	// choose default optional dependencies by default
	with (TestResolver) {
		auto res = new TestResolver([
										P("a:0"): [TreeNodes(P("b"), ics([ic(1)]), DependencyType.optionalDefault)],
										P("b:1"): []
		]);
		assert(res.resolve(TreeNode(P("a"), ic(0))) == [P("b"):ic(1)], to!string(res.resolve(TreeNode(P("a"), ic(0)))));
	}

	// choose optional dependency if non-optional within the dependency tree
	with (TestResolver) {
		auto res = new TestResolver([
										P("a:0"): [TreeNodes(P("b"), ics([ic(1)]), DependencyType.optional), TreeNodes(P("c"), ics([ic(1)]))],
										P("b:1"): [],
										P("c:1"): [TreeNodes(P("b"), ics([ic(1)]))]
		]);
		assert(res.resolve(TreeNode(P("a"), ic(0))) == [P("b"):ic(1), P("c"):ic(1)], to!string(res.resolve(TreeNode(P("a"), ic(0)))));
	}

	// don't choose optional dependency if non-optional outside of final dependency tree
	with (TestResolver) {
		auto res = new TestResolver([
										P("a:0"): [TreeNodes(P("b"), ics([ic(1)]), DependencyType.optional)],
										P("b:1"): [],
										P("preset:0"): [TreeNodes(P("b"), ics([ic(1)]))]
		]);
		assert(res.resolve(TreeNode(P("a"), ic(0))).length == 0, to!string(res.resolve(TreeNode(P("a"), ic(0)))));
	}

	// don't choose optional dependency if non-optional in a non-selected version
	with (TestResolver) {
		auto res = new TestResolver([
										P("a:0"): [TreeNodes(P("b"), ics([ic(1), ic(2)]))],
										P("b:1"): [TreeNodes(P("c"), ics([ic(1)]))],
										P("b:2"): [TreeNodes(P("c"), ics([ic(1)]), DependencyType.optional)],
										P("c:1"): []
		]);
		assert(res.resolve(TreeNode(P("a"), ic(0))) == [P("b"):ic(2)], to!string(res.resolve(TreeNode(P("a"), ic(0)))));
	}

	// make sure non-satisfiable dependencies are not a problem, even if non-optional in some dependencies
	with (TestResolver) {
		auto res = new TestResolver([
										P("a:0"): [TreeNodes(P("b"), ics([ic(1), ic(2)]))],
										P("b:1"): [TreeNodes(P("c"), ics([ic(2)]))],
										P("b:2"): [TreeNodes(P("c"), ics([ic(2)]), DependencyType.optional)],
										P("c:1"): []
		]);
		assert(res.resolve(TreeNode(P("a"), ic(0))) == [P("b"):ic(2)], to!string(res.resolve(TreeNode(P("a"), ic(0)))));
	}

	// check error message for multiple conflicting dependencies
	with (TestResolver) {
		auto res = new TestResolver([
										P("a:0"): [TreeNodes(P("b"), ics([ic(1)])), TreeNodes(P("c"), ics([ic(1)]))],
										P("b:1"): [TreeNodes(P("d"), ics([ic(1)]))],
										P("c:1"): [TreeNodes(P("d"), ics([ic(2)]))],
										P("d:1"): [],
										P("d:2"): []
		]);
		try {
			res.resolve(TreeNode(P("a"), ic(0)));
			assert(false, "Expected resolve to throw.");
		} catch (ResolveException e) {
			assert(e.msg ==
				   "Unresolvable dependencies to package d:"
				   ~ ("\n  b 1 depends on d [1]")
				   ~ ("\n  c 1 depends on d [2]"));
		}
	}

	// check error message for invalid dependency
	with (TestResolver) {
		auto res = new TestResolver([
										P("a:0"): [TreeNodes(P("b"), ics([ic(1)]))]
		]);
		try {
			res.resolve(TreeNode(P("a"), ic(0)));
			assert(false, "Expected resolve to throw.");
		} catch (DependencyLoadException e) {
			assert(e.msg == "Failed to find any versions for package b, referenced by a 0");
		}
	}

	// regression: unresolvable optional dependency skips the remaining dependencies
	with (TestResolver) {
		auto res = new TestResolver([
										P("a:0"): [
											TreeNodes(P("b"), ics([ic(2)]), DependencyType.optional),
											TreeNodes(P("c"), ics([ic(1)]))
			],
										P("b:1"): [],
										P("c:1"): []
		]);
		assert(res.resolve(TreeNode(P("a"), ic(0))) == [P("c"):ic(1)]);
	}
}
