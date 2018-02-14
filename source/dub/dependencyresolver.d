/**
	Dependency configuration/version resolution algorithm.

	Copyright: © 2014 rejectedsoftware e.K.
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
import std.typecons : Nullable;
import std.string : format, indexOf, lastIndexOf;


class DependencyResolver(CONFIGS, CONFIG) {
	static struct TreeNodes {
		string pack;
		CONFIGS configs;
		DependencyType depType = DependencyType.required;

		hash_t toHash() const nothrow @trusted {
			size_t ret = typeid(string).getHash(&pack);
			ret ^= typeid(CONFIGS).getHash(&configs);
			return ret;
		}
		bool opEqual(in ref TreeNodes other) const { return pack == other.pack && configs == other.configs; }
		int opCmp(in ref TreeNodes other) const {
			if (pack != other.pack) return pack < other.pack ? -1 : 1;
			if (configs != other.configs) return configs < other.configs ? -1 : 1;
			return 0;
		}
	}

	static struct TreeNode {
		string pack;
		CONFIG config;

		hash_t toHash() const nothrow @trusted {
			size_t ret = pack.hashOf();
			ret ^= typeid(CONFIG).getHash(&config);
			return ret;
		}
		bool opEqual(in ref TreeNode other) const { return pack == other.pack && config == other.config; }
		int opCmp(in ref TreeNode other) const {
			if (pack != other.pack) return pack < other.pack ? -1 : 1;
			if (config != other.config) return config < other.config ? -1 : 1;
			return 0;
		}
	}

	private static struct PackageConfigs
	{
		static struct Depender
		{
			TreeNode origin;
			TreeNodes dependency;
		}

		// all possible configurations to test for this package
		CONFIG[] allConfigs;

		// determines whether this package has any dependencies, may be
		// different from allConfigs.length > 0 after certain configurations
		// have been filtered out
		bool anyConfig;

		Depender[] origins;
	}

	CONFIG[string] resolve(TreeNode root, bool throw_on_failure = true)
	{
		auto root_base_pack = basePackage(root.pack);

		// find all possible configurations of each possible dependency
		size_t[string] package_indices;
		string[size_t] package_names;
		PackageConfigs[] configs;
		bool[string] maybe_optional_deps;
		bool[TreeNode] visited;

		void findConfigsRec(TreeNode parent, bool parent_unique)
		{
			if (parent in visited) return;
			visited[parent] = true;

			foreach (ch; getChildren(parent)) {
				auto basepack = basePackage(ch.pack);
				auto pidx = configs.length;

				if (ch.depType != DependencyType.required) maybe_optional_deps[ch.pack] = true;

				PackageConfigs config;
				if (auto pi = basepack in package_indices) {
					pidx = *pi;
					config = configs[*pi];
				} else {
					if (basepack == root_base_pack) config.allConfigs = [root.config];
					else config.allConfigs = getAllConfigs(basepack);
					configs ~= config;
					package_indices[basepack] = pidx;
					package_names[pidx] = basepack;
				}

				foreach (c; getSpecificConfigs(basepack, ch))
					if (!config.allConfigs.canFind(c))
						config.allConfigs = c ~ config.allConfigs;

				if (config.allConfigs.length > 0)
					config.anyConfig = true;

				// store package depending on this for better error messages
				config.origins ~= PackageConfigs.Depender(parent, ch);

				// eliminate configurations from which we know that they can't satisfy
				// the uniquely defined root dependencies (==version or ~branch style dependencies)
				if (parent_unique) config.allConfigs = config.allConfigs.filter!(c => matches(ch.configs, c)).array;

				configs[pidx] = config;

				foreach (v; config.allConfigs)
					findConfigsRec(TreeNode(ch.pack, v), parent_unique && config.allConfigs.length == 1);
			}
		}
		findConfigsRec(root, true);

		// append an invalid configuration to denote an unchosen dependency
		// this is used to properly support optional dependencies (when
		// getChildren() returns no configurations for an optional dependency,
		// but getAllConfigs() has already provided an existing list of configs)
		foreach (i, ref cfgs; configs)
			if (cfgs.allConfigs.length == 0 || package_names[i] in maybe_optional_deps)
				cfgs.allConfigs = cfgs.allConfigs ~ CONFIG.invalid;

		logDebug("Configurations used for dependency resolution:");
		foreach (n, i; package_indices) logDebug("  %s (%s%s): %s", n, i, n in maybe_optional_deps ? ", maybe optional" : ", required", configs[i]);

		auto config_indices = new size_t[configs.length];
		config_indices[] = 0;

		visited = null;
		sizediff_t validateConfigs(TreeNode parent, ref ConflictError error)
		{
			import std.algorithm : max;

			if (parent in visited) return -1;

			visited[parent] = true;
			sizediff_t maxcpi = -1;
			sizediff_t parentidx = package_indices.get(basePackage(parent.pack), -1);
			auto parentbase = basePackage(parent.pack);

			// loop over all dependencies
			foreach (ch; getChildren(parent)) {
				auto basepack = basePackage(ch.pack);
				assert(basepack in package_indices, format("%s not in packages %s", basepack, package_indices));

				// get the current config/version of the current dependency
				sizediff_t childidx = package_indices[basepack];
				auto child = configs[childidx];

				if (child.allConfigs.length == 1 && child.allConfigs[0] == CONFIG.invalid) {
					// ignore invalid optional dependencies
					if (ch.depType != DependencyType.required)
						continue;

					if (parentbase == root_base_pack) {
						import std.uni : toLower;
						auto lp = ch.pack.toLower();
						if (lp != ch.pack) {
							logError("Dependency \"%s\" of %s contains upper case letters, but must be lower case.", ch.pack, parent.pack);
							if (getAllConfigs(lp).length) logError("Did you mean \"%s\"?", lp);
						}
						if (child.anyConfig)
							throw new Exception(format("Root package %s reference %s %s cannot be satisfied.\nPackages causing the conflict:\n\t%s",
								parent.pack, ch.pack, ch.configs,
								child.origins.map!(a => a.origin.pack ~ " depends on " ~ a.dependency.configs.to!string).join("\n\t")));
						else
							throw new Exception(format("Root package %s references unknown package %s", parent.pack, ch.pack));
					}
					// choose another parent config to avoid the invalid child
					if (parentidx > maxcpi) {
						error = ConflictError(ConflictError.Kind.invalidDependency, parent, ch, CONFIG.invalid);
						logDiagnostic("%s (ci=%s)", error, parentidx);
						maxcpi = parentidx;
					}
				} else {
					auto config = child.allConfigs[config_indices[childidx]];
					auto chnode = TreeNode(ch.pack, config);

					if (config == CONFIG.invalid || !matches(ch.configs, config)) {
						// ignore missing optional dependencies
						if (config == CONFIG.invalid && ch.depType != DependencyType.required)
							continue;

						// if we are at the root level, we can safely skip the maxcpi computation and instead choose another childidx config
						if (parentbase == root_base_pack) {
							error = ConflictError(ConflictError.Kind.noRootMatch, parent, ch, config);
							return childidx;
						}

						if (childidx > maxcpi) {
							maxcpi = max(childidx, parentidx);
							error = ConflictError(ConflictError.Kind.childMismatch, parent, ch, config);
							logDebug("%s (ci=%s)", error, maxcpi);
						}

						// we know that either the child or the parent needs to be switched
						// to another configuration, no need to continue with other children
						if (config == CONFIG.invalid) break;
					}

					maxcpi = max(maxcpi, validateConfigs(chnode, error));
				}
			}
			return maxcpi;
		}

		Nullable!ConflictError first_error;
		size_t loop_counter = 0;

		// Leave the possibility to opt-out from the loop limit
		import std.process : environment;
		bool no_loop_limit = environment.get("DUB_NO_RESOLVE_LIMIT") !is null;

		while (true) {
			assert(no_loop_limit || loop_counter++ < 1_000_000,
				"The dependency resolution process is taking too long. The"
				~ " dependency graph is likely hitting a pathological case in"
				~ " the resolution algorithm. Please file a bug report at"
				~ " https://github.com/dlang/dub/issues and mention the package"
				~ " recipe that reproduces this error.");

			// check if the current combination of configurations works out
			visited = null;
			ConflictError error;
			auto conflict_index = validateConfigs(root, error);
			if (first_error.isNull) first_error = error;

			// print out current iteration state
			logDebug("Interation (ci=%s) %s", conflict_index, {
				import std.array : join;
				auto cs = new string[configs.length];
				foreach (p, i; package_indices) {
					if (configs[i].allConfigs.length)
						cs[i] = p~" "~configs[i].allConfigs[config_indices[i]].to!string~(i >= 0 && i >= conflict_index ? " (C)" : "");
					else cs[i] = p ~ " [no config]";
				}
				return cs.join(", ");
			}());

			if (conflict_index < 0) {
				CONFIG[string] ret;
				foreach (p, i; package_indices)
					if (configs[i].allConfigs.length) {
						auto cfg = configs[i].allConfigs[config_indices[i]];
						if (cfg != CONFIG.invalid) ret[p] = cfg;
					}
				logDebug("Resolved dependencies before optional-purge: %s", ret.byKey.map!(k => k~" "~ret[k].to!string));
				purgeOptionalDependencies(root, ret);
				logDebug("Resolved dependencies after optional-purge: %s", ret.byKey.map!(k => k~" "~ret[k].to!string));
				return ret;
			}

			// find the next combination of configurations
			foreach_reverse (pi, ref i; config_indices) {
				if (pi > conflict_index) i = 0;
				else if (++i >= configs[pi].allConfigs.length) i = 0;
				else break;
			}
			if (config_indices.all!"a==0") {
				if (throw_on_failure) throw new Exception(format("Could not find a valid dependency tree configuration: %s", first_error.get));
				else return null;
			}
		}
	}

	protected abstract CONFIG[] getAllConfigs(string pack);
	protected abstract CONFIG[] getSpecificConfigs(string pack, TreeNodes nodes);
	protected abstract TreeNodes[] getChildren(TreeNode node);
	protected abstract bool matches(CONFIGS configs, CONFIG config);

	private void purgeOptionalDependencies(TreeNode root, ref CONFIG[string] configs)
	{
		bool[string] required;
		bool[string] visited;

		void markRecursively(TreeNode node)
		{
			if (node.pack in visited) return;
			visited[node.pack] = true;
			required[basePackage(node.pack)] = true;
			foreach (dep; getChildren(node).filter!(dep => dep.depType != DependencyType.optional))
				if (auto dp = basePackage(dep.pack) in configs)
					markRecursively(TreeNode(dep.pack, *dp));
		}

		// recursively mark all required dependencies of the concrete dependency tree
		markRecursively(root);

		// remove all un-marked configurations
		foreach (p; configs.keys.dup)
			if (p !in required)
				configs.remove(p);
	}

	private struct ConflictError {
		enum Kind {
			none,
			noRootMatch,
			childMismatch,
			invalidDependency
		}

		Kind kind;
		TreeNode parent;
		TreeNodes child;
		CONFIG config;

		string toString()
		const {
			final switch (kind) {
				case Kind.none: return "no error";
				case Kind.noRootMatch:
					return "No match for dependency %s %s of %s"
						.format(child.pack, child.configs, parent.pack);
				case Kind.childMismatch:
					return "Dependency %s -> %s %s mismatches with selected version %s"
						.format(parent.pack, child.pack, child.configs, config);
				case Kind.invalidDependency:
					return "Package %s contains invalid dependency %s (no version candidates)"
						.format(parent.pack, child.pack);
			}
		}
	}
}

enum DependencyType {
	required,
	optionalDefault,
	optional
}

private string basePackage(string p)
{
	auto idx = indexOf(p, ':');
	if (idx < 0) return p;
	return p[0 .. idx];
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
		protected override IntConfig[] getAllConfigs(string pack) {
			auto ret = appender!(IntConfig[]);
			foreach (p; m_children.byKey) {
				if (p.length <= pack.length+1) continue;
				if (p[0 .. pack.length] != pack || p[pack.length] != ':') continue;
				auto didx = p.lastIndexOf(':');
				ret ~= ic(p[didx+1 .. $].to!uint);
			}
			ret.data.sort!"a>b"();
			return ret.data;
		}
		protected override IntConfig[] getSpecificConfigs(string pack, TreeNodes nodes) { return null; }
		protected override TreeNodes[] getChildren(TreeNode node) { return m_children.get(node.pack ~ ":" ~ node.config.to!string(), null); }
		protected override bool matches(IntConfigs configs, IntConfig config) { return configs.canFind(config); }
	}

	// properly back up if conflicts are detected along the way (d:2 vs d:1)
	with (TestResolver) {
		auto res = new TestResolver([
			"a:0": [TreeNodes("b", ics([ic(2), ic(1)])), TreeNodes("d", ics([ic(1)])), TreeNodes("e", ics([ic(2), ic(1)]))],
			"b:1": [TreeNodes("c", ics([ic(2), ic(1)])), TreeNodes("d", ics([ic(1)]))],
			"b:2": [TreeNodes("c", ics([ic(3), ic(2)])), TreeNodes("d", ics([ic(2), ic(1)]))],
			"c:1": [], "c:2": [], "c:3": [],
			"d:1": [], "d:2": [],
			"e:1": [], "e:2": [],
		]);
		assert(res.resolve(TreeNode("a", ic(0))) == ["b":ic(2), "c":ic(3), "d":ic(1), "e":ic(2)], format("%s", res.resolve(TreeNode("a", ic(0)))));
	}

	// handle cyclic dependencies gracefully
	with (TestResolver) {
		auto res = new TestResolver([
			"a:0": [TreeNodes("b", ics([ic(1)]))],
			"b:1": [TreeNodes("b", ics([ic(1)]))]
		]);
		assert(res.resolve(TreeNode("a", ic(0))) == ["b":ic(1)]);
	}

	// don't choose optional dependencies by default
	with (TestResolver) {
		auto res = new TestResolver([
			"a:0": [TreeNodes("b", ics([ic(1)]), DependencyType.optional)],
			"b:1": []
		]);
		assert(res.resolve(TreeNode("a", ic(0))).length == 0, to!string(res.resolve(TreeNode("a", ic(0)))));
	}

	// choose default optional dependencies by default
	with (TestResolver) {
		auto res = new TestResolver([
			"a:0": [TreeNodes("b", ics([ic(1)]), DependencyType.optionalDefault)],
			"b:1": []
		]);
		assert(res.resolve(TreeNode("a", ic(0))) == ["b":ic(1)], to!string(res.resolve(TreeNode("a", ic(0)))));
	}

	// choose optional dependency if non-optional within the dependency tree
	with (TestResolver) {
		auto res = new TestResolver([
			"a:0": [TreeNodes("b", ics([ic(1)]), DependencyType.optional), TreeNodes("c", ics([ic(1)]))],
			"b:1": [],
			"c:1": [TreeNodes("b", ics([ic(1)]))]
		]);
		assert(res.resolve(TreeNode("a", ic(0))) == ["b":ic(1), "c":ic(1)], to!string(res.resolve(TreeNode("a", ic(0)))));
	}

	// don't choose optional dependency if non-optional outside of final dependency tree
	with (TestResolver) {
		auto res = new TestResolver([
			"a:0": [TreeNodes("b", ics([ic(1)]), DependencyType.optional)],
			"b:1": [],
			"preset:0": [TreeNodes("b", ics([ic(1)]))]
		]);
		assert(res.resolve(TreeNode("a", ic(0))).length == 0, to!string(res.resolve(TreeNode("a", ic(0)))));
	}

	// don't choose optional dependency if non-optional in a non-selected version
	with (TestResolver) {
		auto res = new TestResolver([
			"a:0": [TreeNodes("b", ics([ic(1), ic(2)]))],
			"b:1": [TreeNodes("c", ics([ic(1)]))],
			"b:2": [TreeNodes("c", ics([ic(1)]), DependencyType.optional)],
			"c:1": []
		]);
		assert(res.resolve(TreeNode("a", ic(0))) == ["b":ic(2)], to!string(res.resolve(TreeNode("a", ic(0)))));
	}

	// make sure non-satisfyable dependencies are not a problem, even if non-optional in some dependencies
	with (TestResolver) {
		auto res = new TestResolver([
			"a:0": [TreeNodes("b", ics([ic(1), ic(2)]))],
			"b:1": [TreeNodes("c", ics([ic(2)]))],
			"b:2": [TreeNodes("c", ics([ic(2)]), DependencyType.optional)],
			"c:1": []
		]);
		assert(res.resolve(TreeNode("a", ic(0))) == ["b":ic(2)], to!string(res.resolve(TreeNode("a", ic(0)))));
	}
}
