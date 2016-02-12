/**
	Dependency configuration/version resolution algorithm.

	Copyright: © 2014 rejectedsoftware e.K.
	License: Subject to the terms of the MIT license, as written in the included LICENSE.txt file.
	Authors: Sönke Ludwig
*/
module dub.dependencyresolver;

import dub.dependency;
import dub.internal.vibecompat.core.log;

import std.algorithm : all, canFind, filter, sort;
import std.array : appender, array;
import std.conv : to;
import std.exception : enforce;
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
			size_t ret = typeid(string).getHash(&pack);
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

	CONFIG[string] resolve(TreeNode root, bool throw_on_failure = true)
	{
		auto root_base_pack = rootPackage(root.pack);

		// find all possible configurations of each possible dependency
		size_t[string] package_indices;
		string[size_t] package_names;
		CONFIG[][] all_configs;
		bool[string] required_deps;
		bool[TreeNode] visited;
		void findConfigsRec(TreeNode parent, bool parent_unique)
		{
			if (parent in visited) return;
			visited[parent] = true;

			foreach (ch; getChildren(parent)) {
				auto basepack = rootPackage(ch.pack);
				auto pidx = all_configs.length;

				if (ch.depType == DependencyType.required) required_deps[ch.pack] = true;

				CONFIG[] configs;
				if (auto pi = basepack in package_indices) {
					pidx = *pi;
					configs = all_configs[*pi];
				} else {
					if (basepack == root_base_pack) configs = [root.config];
					else configs = getAllConfigs(basepack);
					all_configs ~= configs;
					package_indices[basepack] = pidx;
					package_names[pidx] = basepack;
				}

				configs = getSpecificConfigs(basepack, ch) ~ configs;

				// eliminate configurations from which we know that they can't satisfy
				// the uniquely defined root dependencies (==version or ~branch style dependencies)
				if (parent_unique) configs = configs.filter!(c => matches(ch.configs, c)).array;

				all_configs[pidx] = configs;

				foreach (v; configs)
					findConfigsRec(TreeNode(ch.pack, v), parent_unique && configs.length == 1);
			}
		}
		findConfigsRec(root, true);

		// append an invalid configuration to denote an unchosen dependency
		// this is used to properly support optional dependencies (when
		// getChildren() returns no configurations for an optional dependency,
		// but getAllConfigs() has already provided an existing list of configs)
		foreach (i, ref cfgs; all_configs)
			if (cfgs.length == 0 || package_names[i] !in required_deps)
				cfgs = cfgs ~ CONFIG.invalid;

		logDebug("Configurations used for dependency resolution:");
		foreach (n, i; package_indices) logDebug("  %s (%s%s): %s", n, i, n in required_deps ? "" : ", optional", all_configs[i]);

		auto config_indices = new size_t[all_configs.length];
		config_indices[] = 0;

		string last_error;

		visited = null;
		sizediff_t validateConfigs(TreeNode parent, ref string error)
		{
			import std.algorithm : max;

			if (parent in visited) return -1;

			visited[parent] = true;
			sizediff_t maxcpi = -1;
			sizediff_t parentidx = package_indices.get(rootPackage(parent.pack), -1);
			auto parentbase = rootPackage(parent.pack);

			// loop over all dependencies
			foreach (ch; getChildren(parent)) {
				auto basepack = rootPackage(ch.pack);
				assert(basepack in package_indices, format("%s not in packages %s", basepack, package_indices));

				// get the current config/version of the current dependency
				sizediff_t childidx = package_indices[basepack];
				if (all_configs[childidx] == [CONFIG.invalid]) {
					// ignore invalid optional dependencies
					if (ch.depType != DependencyType.required)
						continue;

					enforce(parentbase != root_base_pack, format("Root package %s contains reference to invalid package %s %s", parent.pack, ch.pack, ch.configs));
					// choose another parent config to avoid the invalid child
					if (parentidx > maxcpi) {
						error = format("Package %s contains invalid dependency %s", parent.pack, ch.pack);
						logDiagnostic("%s (ci=%s)", error, parentidx);
						maxcpi = parentidx;
					}
				} else {
					auto config = all_configs[childidx][config_indices[childidx]];
					auto chnode = TreeNode(ch.pack, config);

					if (config == CONFIG.invalid || !matches(ch.configs, config)) {
						// ignore missing optional dependencies
						if (config == CONFIG.invalid && ch.depType != DependencyType.required)
							continue;

						// if we are at the root level, we can safely skip the maxcpi computation and instead choose another childidx config
						if (parentbase == root_base_pack) {
							error = format("No match for dependency %s %s of %s", ch.pack, ch.configs, parent.pack);
							return childidx;
						}

						if (childidx > maxcpi) {
							maxcpi = max(childidx, parentidx);
							error = format("Dependency %s -> %s %s mismatches with selected version %s", parent.pack, ch.pack, ch.configs, config);
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

		string first_error;

		while (true) {
			// check if the current combination of configurations works out
			visited = null;
			string error;
			auto conflict_index = validateConfigs(root, error);
			if (first_error !is null) first_error = error;

			// print out current iteration state
			logDebug("Interation (ci=%s) %s", conflict_index, {
				import std.array : join;
				auto cs = new string[all_configs.length];
				foreach (p, i; package_indices) {
					if (all_configs[i].length)
						cs[i] = p~" "~all_configs[i][config_indices[i]].to!string~(i >= 0 && i >= conflict_index ? " (C)" : "");
					else cs[i] = p ~ " [no config]";
				}
				return cs.join(", ");
			}());

			if (conflict_index < 0) {
				CONFIG[string] ret;
				foreach (p, i; package_indices)
					if (all_configs[i].length) {
						auto cfg = all_configs[i][config_indices[i]];
						if (cfg != CONFIG.invalid) ret[p] = cfg;
					}
				purgeOptionalDependencies(root, ret);
				return ret;
			}

			// find the next combination of configurations
			foreach_reverse (pi, ref i; config_indices) {
				if (pi > conflict_index) i = 0;
				else if (++i >= all_configs[pi].length) i = 0;
				else break;
			}
			if (config_indices.all!"a==0") {
				if (throw_on_failure) throw new Exception("Could not find a valid dependency tree configuration: "~first_error);
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

		void markRecursively(TreeNode node)
		{
			if (node.pack in required) return;
			required[node.pack] = true;
			foreach (dep; getChildren(node).filter!(dep => dep.depType != DependencyType.optional))
				if (auto dp = rootPackage(dep.pack) in configs)
					markRecursively(TreeNode(dep.pack, *dp));
		}

		// recursively mark all required dependencies of the concrete dependency tree
		markRecursively(root);

		// remove all un-marked configurations
		foreach (p; configs.keys.dup)
			if (p !in required)
				configs.remove(p);
	}
}

enum DependencyType {
	required,
	optionalDefault,
	optional
}

private string rootPackage(string p)
{
	auto idx = indexOf(p, ":");
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
}
