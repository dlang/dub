/+ dub.sdl:
name "issue2348-single"
buildType "test" {
    buildOptions "syntaxOnly"
    postBuildCommands "echo xxx"
}
+/
