/**
	Dependency configuration/version resolution algorithm.

	Copyright: © 2014 rejectedsoftware e.K.
	License: Subject to the terms of the MIT license, as written in the included LICENSE.txt file.
	Authors: Sönke Ludwig
*/
module dub.dependencyresolver;

import dub.dependency;
import dub.internal.vibecompat.core.log;

import std.algorithm : all, canFind, sort;
import std.array : appender;
import std.conv : to;
import std.exception : enforce;
import std.string : format, indexOf, lastIndexOf;


class DependencyResolver(CONFIGS, CONFIG) {
	static struct TreeNodes {
		string pack;
		CONFIGS configs;

		hash_t toHash() const nothrow @trusted {
			try {
				size_t ret = typeid(string).getHash(&pack);
				ret ^= typeid(CONFIGS).getHash(&configs);
				return ret;
			} catch assert(false);
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
			try {
				size_t ret = typeid(string).getHash(&pack);
				ret ^= typeid(CONFIG).getHash(&config);
				return ret;
			} catch assert(false);
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
		static string rootPackage(string p) {
			auto idx = indexOf(p, ":");
			if (idx < 0) return p;
			return p[0 .. idx];
		}

		size_t[string] package_indices;
		CONFIG[][] all_configs;
		bool[TreeNode] visited;
		void findConfigsRec(TreeNode parent)
		{
			if (parent in visited) return;
			visited[parent] = true;

			foreach (ch; getChildren(parent)) {
				auto basepack = rootPackage(ch.pack);
				auto pidx = all_configs.length;
				CONFIG[] configs;
				if (auto pi = basepack in package_indices) {
					pidx = *pi;
					configs = all_configs[*pi];
				} else {
					configs = getAllConfigs(basepack);
					all_configs ~= configs;
					package_indices[basepack] = pidx;
				}

				configs = getSpecificConfigs(ch) ~ configs;

				all_configs[pidx] = configs;

				foreach (v; all_configs[pidx])
					findConfigsRec(TreeNode(ch.pack, v));
			}
		}
		findConfigsRec(root);

		logDebug("Configurations used for dependency resolution:");
		foreach (n, i; package_indices) logDebug("  %s (%s): %s", n, i, all_configs[i]);

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

			// loop over all dependencies
			foreach (ch; getChildren(parent)) {
				auto basepack = rootPackage(ch.pack);
				assert(basepack in package_indices, format("%s not in packages %s", basepack, package_indices));

				// get the current config/version of the current dependency
				sizediff_t childidx = package_indices[basepack];
				if (!all_configs[childidx].length) {
					enforce(parentidx >= 0, format("Root package %s contains reference to invalid package %s", parent.pack, ch.pack));
					// choose another parent config to avoid the invalid child
					if (parentidx > maxcpi) {
						error = format("Package %s contains invalid dependency %s", parent.pack, ch.pack);
						logDiagnostic("%s (ci=%s)", error, parentidx);
						maxcpi = parentidx;
					}
					enforce(parent != root, "Invalid dependecy %s referenced by the root package.");
				} else {
					auto config = all_configs[childidx][config_indices[childidx]];
					auto chnode = TreeNode(ch.pack, config);
					if (!matches(ch.configs, config)) {
						// if we are at the root level, we can safely skip the maxcpi computation and instead choose another childidx config
						if (parent == root) {
							error = format("No match for dependency %s %s of %s", ch.pack, ch.configs, parent.pack);
							return childidx;
						}

						if (childidx > maxcpi) {
							maxcpi = max(childidx, parentidx);
							error = format("Dependency %s -> %s %s mismatches with selected version %s", parent.pack, ch.pack, ch.configs, config);
							logDebug("%s (ci=%s)", error, maxcpi);
						}
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
			if (!first_error) first_error = error;

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
					if (all_configs[i].length)
						ret[p] = all_configs[i][config_indices[i]];
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
	protected abstract CONFIG[] getSpecificConfigs(TreeNodes nodes);
	protected abstract TreeNodes[] getChildren(TreeNode node);
	protected abstract bool matches(CONFIGS configs, CONFIG config);
}


unittest {
	static class TestResolver : DependencyResolver!(uint[], uint) {
		private TreeNodes[][string] m_children;
		this(TreeNodes[][string] children) { m_children = children; }
		protected override uint[] getAllConfigs(string pack) {
			auto ret = appender!(uint[]);
			foreach (p; m_children.byKey) {
				if (p.length <= pack.length+1) continue;
				if (p[0 .. pack.length] != pack || p[pack.length] != ':') continue;
				auto didx = p.lastIndexOf(':');
				ret ~= p[didx+1 .. $].to!uint;
			}
			ret.data.sort!"a>b"();
			return ret.data;
		}
		protected override uint[] getSpecificConfigs(TreeNodes nodes) { return null; }
		protected override TreeNodes[] getChildren(TreeNode node) { return m_children.get(node.pack ~ ":" ~ node.config.to!string(), null); }
		protected override bool matches(uint[] configs, uint config) { return configs.canFind(config); }
	}

	// properly back up if conflicts are detected along the way (d:2 vs d:1)
	with (TestResolver) {
		auto res = new TestResolver([
			"a:0": [TreeNodes("b", [2, 1]), TreeNodes("d", [1]), TreeNodes("e", [2, 1])],
			"b:1": [TreeNodes("c", [2, 1]), TreeNodes("d", [1])],
			"b:2": [TreeNodes("c", [3, 2]), TreeNodes("d", [2, 1])],
			"c:1": [], "c:2": [], "c:3": [],
			"d:1": [], "d:2": [],
			"e:1": [], "e:2": [],
		]);
		assert(res.resolve(TreeNode("a", 0)) == ["b":2u, "c":3u, "d":1u, "e":2u], format("%s", res.resolve(TreeNode("a", 0))));
	}

	// handle cyclic dependencies gracefully
	with (TestResolver) {
		auto res = new TestResolver([
			"a:0": [TreeNodes("b", [1])],
			"b:1": [TreeNodes("b", [1])]
		]);
		assert(res.resolve(TreeNode("a", 0)) == ["b":1u]);
	}
}
