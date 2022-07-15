/**
 * Contains type definition for `dub.selections.json`
 */
module dub.recipe.selection;

import dub.dependency;

public struct Selected
{
    /// The current version of the file format
    public uint fileVersion;

    /// The selected package and their matching versions
    public Dependency[string] versions;
}
