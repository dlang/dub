/**
	Dependency configuration/version resolution algorithm.

	Copyright: © 2014-2018 Sönke Ludwig
	License: Subject to the terms of the MIT license, as written in the included LICENSE.txt file.
	Authors: Sönke Ludwig
*/
module dub.dependencyresolver;

import dub.dependency;
import dub.internal.logging;

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
	/// Maximum number of loop rounds to do
	protected ulong loop_limit;

	/**
	 * Construct an instance of this class
	 *
	 * Params:
	 *	 limit = Maximum number of loop rounds to do
	 */
	public this (ulong limit) inout scope @safe pure nothrow @nogc
	{
		this.loop_limit = limit;
	}

	/// Compatibility overload
	deprecated("Use the overload that accepts a `ulong limit` argument")
	public this () scope @safe
	{
		// Leave the possibility to opt-out from the loop limit
		import std.process : environment;
		if (environment.get("DUB_NO_RESOLVE_LIMIT") !is null)
			this(ulong.max);
		else
			this(1_000_000);
	}

	/** Encapsulates a list of outgoing edges in the dependency graph.

		A value of this type represents a single dependency with multiple
		possible configurations for the target package.
	*/
	static struct TreeNodes {
		PackageName pack;
		CONFIGS configs;
		DependencyType depType = DependencyType.required;

		size_t toHash() const nothrow @trusted {
			size_t ret = typeid(string).getHash(&pack);
			ret ^= typeid(CONFIGS).getHash(&configs);
			return ret;
		}
		bool opEqual(const scope ref TreeNodes other) const { return pack == other.pack && configs == other.configs; }
		int opCmp(const scope ref TreeNodes other) const {
			if (pack != other.pack) return pack < other.pack ? -1 : 1;
			if (configs != other.configs) return configs < other.configs ? -1 : 1;
			return 0;
		}
	}

	/** A single node in the dependency graph.

		Nodes are a combination of a package and a single package configuration.
	*/
	static struct TreeNode {
		PackageName pack;
		CONFIG config;

		size_t toHash() const nothrow @trusted {
			size_t ret = pack.hashOf();
			ret ^= typeid(CONFIG).getHash(&config);
			return ret;
		}
		bool opEqual(const scope ref TreeNode other) const { return pack == other.pack && config == other.config; }
		int opCmp(const scope ref TreeNode other) const {
			if (pack != other.pack) return pack < other.pack ? -1 : 1;
			if (config != other.config) return config < other.config ? -1 : 1;
			return 0;
		}
	}

	CONFIG[PackageName] resolve(TreeNode root, bool throw_on_failure = true)
	{
		auto rootbase = root.pack.main;

		// build up the dependency graph, eliminating as many configurations/
		// versions as possible
		ResolveContext context;
		context.configs[rootbase] = [ResolveConfig(root.config, true)];
		ulong loop_counter = this.loop_limit;
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

	protected abstract CONFIG[] getAllConfigs(in PackageName pack);
	protected abstract CONFIG[] getSpecificConfigs(in PackageName pack, TreeNodes nodes);
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
		void[0][PackageName] visited;

		/// The finally chosen configurations for each package
		CONFIG[PackageName] result;

		/// The set of available configurations for each package
		ResolveConfig[][PackageName] configs;

		/// Determines if a certain package has already been processed
		bool isVisited(in PackageName package_) const { return (package_ in visited) !is null; }

		/// Marks a package as processed
		void setVisited(in PackageName package_) { visited[package_] = (void[0]).init; }

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
	private void constrain(TreeNode n, ref ResolveContext context, ref ulong max_iterations)
	{
		auto base = n.pack.main;
		assert(base in context.configs);
		if (context.isVisited(n.pack)) return;
		context.setVisited(n.pack);
		context.result[base] = n.config;
		foreach (j, ref sc; context.configs[base])
			sc.included = sc.config == n.config;

		auto dependencies = getChildren(n);

		foreach (dep; dependencies) {
			// lazily load all dependency configurations
			auto depbase = dep.pack.main;
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
		ref ResolveContext context, ref ulong max_iterations)
	{
		if (depidx >= dependencies.length) return;

		assert (--max_iterations > 0,
			"The dependency resolution process is taking too long. The"
			~ " dependency graph is likely hitting a pathological case in"
			~ " the resolution algorithm. Please file a bug report at"
			~ " https://github.com/dlang/dub/issues and mention the package"
			~ " recipe that reproduces this error.");

		auto dep = &dependencies[depidx];
		auto depbase = dep.pack.main;
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
			dep.pack, dep.configs, n.pack, n.config));
	}

	private void purgeOptionalDependencies(TreeNode root, ref CONFIG[PackageName] configs)
	{
		bool[PackageName] required;
		bool[PackageName] visited;

		void markRecursively(TreeNode node)
		{
			if (node.pack in visited) return;
			visited[node.pack] = true;
			required[node.pack.main] = true;
			foreach (dep; getChildren(node).filter!(dep => dep.depType != DependencyType.optional))
				if (auto dp = dep.pack.main in configs)
					markRecursively(TreeNode(dep.pack, *dp));
		}

		// recursively mark all required dependencies of the concrete dependency tree
		markRecursively(root);

		// remove all unmarked configurations
		foreach (p; configs.keys.dup)
			if (p !in required)
				configs.remove(p);
	}

	final class ResolveException : Exception {
		import std.range : chain, only;
		import std.typecons : tuple;

		PackageName failedNode;

		this(TreeNode parent, TreeNodes dep, const scope ref ResolveContext context, string file = __FILE__, size_t line = __LINE__)
		{
			auto m = format("Unresolvable dependencies to package %s:", dep.pack.main);
			super(m, file, line);

			this.failedNode = dep.pack;

			auto failbase = failedNode.main;

			// get the list of all dependencies to the failed package
			auto deps = context.visited.byKey
				.filter!(p => !!(p.main in context.result))
				.map!(p => TreeNode(p, context.result[p.main]))
				.map!(n => getChildren(n)
					.filter!(d => d.pack.main == failbase)
					.map!(d => tuple(n, d))
				)
				.join
				.sort!((a, b) => a[0].pack < b[0].pack);

			foreach (d; deps) {
				// filter out trivial self-dependencies
				if (d[0].pack.main == failbase
					&& matches(d[1].configs, d[0].config))
					continue;
				msg ~= format("\n  %s %s depends on %s %s", d[0].pack, d[0].config, d[1].pack, d[1].configs);
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
	static PackageName pn(string name)		{ return PackageName(name); }

	static class TestResolver : DependencyResolver!(IntConfigs, IntConfig) {
		private TreeNodes[][string] m_children;
		this(TreeNodes[][string] children) { super(ulong.max); m_children = children; }
		protected override IntConfig[] getAllConfigs(in PackageName pack) {
			auto ret = appender!(IntConfig[]);
			foreach (p_; m_children.byKey) {
				// Note: We abuse subpackage notation to store configs
				const p = PackageName(p_);
				if (p.main != pack.main) continue;
				ret ~= ic(p.sub.to!uint);
			}
			ret.data.sort!"a>b"();
			return ret.data;
		}
		protected override IntConfig[] getSpecificConfigs(in PackageName pack, TreeNodes nodes) { return null; }
		protected override TreeNodes[] getChildren(TreeNode node) {
			assert(node.pack.sub.length == 0);
			return m_children.get(node.pack.toString() ~ ":" ~ node.config.to!string(), null);
		}
		protected override bool matches(IntConfigs configs, IntConfig config) { return configs.canFind(config); }
	}

	// properly back up if conflicts are detected along the way (d:2 vs d:1)
	with (TestResolver) {
		auto res = new TestResolver([
			"a:0": [TreeNodes(pn("b"), ics([ic(2), ic(1)])), TreeNodes(pn("d"), ics([ic(1)])), TreeNodes(pn("e"), ics([ic(2), ic(1)]))],
			"b:1": [TreeNodes(pn("c"), ics([ic(2), ic(1)])), TreeNodes(pn("d"), ics([ic(1)]))],
			"b:2": [TreeNodes(pn("c"), ics([ic(3), ic(2)])), TreeNodes(pn("d"), ics([ic(2), ic(1)]))],
			"c:1": [], "c:2": [], "c:3": [],
			"d:1": [], "d:2": [],
			"e:1": [], "e:2": [],
		]);
		assert(res.resolve(TreeNode(pn("a"), ic(0))) == [pn("b"):ic(2), pn("c"):ic(3), pn("d"):ic(1), pn("e"):ic(2)],
			format("%s", res.resolve(TreeNode(pn("a"), ic(0)))));
	}

	// handle cyclic dependencies gracefully
	with (TestResolver) {
		auto res = new TestResolver([
			"a:0": [TreeNodes(pn("b"), ics([ic(1)]))],
			"b:1": [TreeNodes(pn("b"), ics([ic(1)]))]
		]);
		assert(res.resolve(TreeNode(pn("a"), ic(0))) == [pn("b"):ic(1)]);
	}

	// don't choose optional dependencies by default
	with (TestResolver) {
		auto res = new TestResolver([
			"a:0": [TreeNodes(pn("b"), ics([ic(1)]), DependencyType.optional)],
			"b:1": []
		]);
		assert(res.resolve(TreeNode(pn("a"), ic(0))).length == 0,
			to!string(res.resolve(TreeNode(pn("a"), ic(0)))));
	}

	// choose default optional dependencies by default
	with (TestResolver) {
		auto res = new TestResolver([
			"a:0": [TreeNodes(pn("b"), ics([ic(1)]), DependencyType.optionalDefault)],
			"b:1": []
		]);
		assert(res.resolve(TreeNode(pn("a"), ic(0))) == [pn("b"):ic(1)],
			to!string(res.resolve(TreeNode(pn("a"), ic(0)))));
	}

	// choose optional dependency if non-optional within the dependency tree
	with (TestResolver) {
		auto res = new TestResolver([
			"a:0": [TreeNodes(pn("b"), ics([ic(1)]), DependencyType.optional), TreeNodes(pn("c"), ics([ic(1)]))],
			"b:1": [],
			"c:1": [TreeNodes(pn("b"), ics([ic(1)]))]
		]);
		assert(res.resolve(TreeNode(pn("a"), ic(0))) == [pn("b"):ic(1), pn("c"):ic(1)],
			to!string(res.resolve(TreeNode(pn("a"), ic(0)))));
	}

	// don't choose optional dependency if non-optional outside of final dependency tree
	with (TestResolver) {
		auto res = new TestResolver([
			"a:0": [TreeNodes(pn("b"), ics([ic(1)]), DependencyType.optional)],
			"b:1": [],
			"preset:0": [TreeNodes(pn("b"), ics([ic(1)]))]
		]);
		assert(res.resolve(TreeNode(pn("a"), ic(0))).length == 0,
			to!string(res.resolve(TreeNode(pn("a"), ic(0)))));
	}

	// don't choose optional dependency if non-optional in a non-selected version
	with (TestResolver) {
		auto res = new TestResolver([
			"a:0": [TreeNodes(pn("b"), ics([ic(1), ic(2)]))],
			"b:1": [TreeNodes(pn("c"), ics([ic(1)]))],
			"b:2": [TreeNodes(pn("c"), ics([ic(1)]), DependencyType.optional)],
			"c:1": []
		]);
		assert(res.resolve(TreeNode(pn("a"), ic(0))) == [pn("b"):ic(2)],
			to!string(res.resolve(TreeNode(pn("a"), ic(0)))));
	}

	// make sure non-satisfiable dependencies are not a problem, even if non-optional in some dependencies
	with (TestResolver) {
		auto res = new TestResolver([
			"a:0": [TreeNodes(pn("b"), ics([ic(1), ic(2)]))],
			"b:1": [TreeNodes(pn("c"), ics([ic(2)]))],
			"b:2": [TreeNodes(pn("c"), ics([ic(2)]), DependencyType.optional)],
			"c:1": []
		]);
		assert(res.resolve(TreeNode(pn("a"), ic(0))) == [pn("b"):ic(2)],
			to!string(res.resolve(TreeNode(pn("a"), ic(0)))));
	}

	// check error message for multiple conflicting dependencies
	with (TestResolver) {
		auto res = new TestResolver([
			"a:0": [TreeNodes(pn("b"), ics([ic(1)])), TreeNodes(pn("c"), ics([ic(1)]))],
			"b:1": [TreeNodes(pn("d"), ics([ic(1)]))],
			"c:1": [TreeNodes(pn("d"), ics([ic(2)]))],
			"d:1": [],
			"d:2": []
		]);
		try {
			res.resolve(TreeNode(pn("a"), ic(0)));
			assert(false, "Expected resolve to throw.");
		} catch (ResolveException e) {
			assert(e.msg ==
				"Unresolvable dependencies to package d:"
				~ "\n  b 1 depends on d [1]"
				~ "\n  c 1 depends on d [2]");
		}
	}

	// check error message for invalid dependency
	with (TestResolver) {
		auto res = new TestResolver([
			"a:0": [TreeNodes(pn("b"), ics([ic(1)]))]
		]);
		try {
			res.resolve(TreeNode(pn("a"), ic(0)));
			assert(false, "Expected resolve to throw.");
		} catch (DependencyLoadException e) {
			assert(e.msg == "Failed to find any versions for package b, referenced by a 0");
		}
	}

	// regression: unresolvable optional dependency skips the remaining dependencies
	with (TestResolver) {
		auto res = new TestResolver([
			"a:0": [
				TreeNodes(pn("b"), ics([ic(2)]), DependencyType.optional),
				TreeNodes(pn("c"), ics([ic(1)]))
			],
			"b:1": [],
			"c:1": []
		]);
		assert(res.resolve(TreeNode(pn("a"), ic(0))) == [pn("c"):ic(1)]);
	}
}
