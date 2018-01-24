## Architecture

![architecture](architecture.png)

## Terminology

<dl>
    <dt>Package</dt>
    <dd>A locally available version of a dub package, consisting of sources, binaries, and described by it's dub.sdl/json file.</dd>
    <dt>PackageSupplier</dt>
    <dd>A source to search and fetch package versions (zip bundles) from.</dd>
    <dt>PackageManager</dt>
    <dd>Responsible to manage packages (fetched or add-local packages), and overrides.</dd>
    <dt>PackageRecipe</dt>
    <dd>Abstract description of package sources, targets, configurations, and build settings.</dd>
    <dt>Generator</dt>
    <dd>Responsible for generating a build recipe (e.g. CMakeLists.txt, VS .sln) for a package, config, and build type. Direct builds (dmd, rdmd) are also implemented as generators.</dt>
    <dt>PackageDependency</dt>
    <dd>Unresolved, abstract specification of a dependency, e.g. <code>dependency "vibe-d" version="~>0.8.1"</code>.</dd>
    <dt>DependencyResolver</dt>
    <dd>Algorithm to resolve package dependencies to specific package versions (dub.selections.json), searching available package versions in package suppliers.</dd>
    <dt>Target</dt>
    <dd>A build output like a static library or executable.</dd>
    <dt>BuildCache</dt>
    <dd>Caches targets for a specific build id.</dd>
</dl>
