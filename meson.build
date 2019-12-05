project(
    'dub',
    'd',
)

compiler = meson.get_compiler('d')
if compiler.has_argument('-version=DubCurl')
    add_project_arguments(
        '-version=DubUseCurl',
        '-version=DubApplication',
        language: 'd'
    )
elif compiler.has_argument('--d-version=DubUseCurl')
    add_project_arguments(
        '--d-version=DubUseCurl',
        '--d-version=DubApplication',
        language: 'd'
    )
else
    add_project_arguments(
        '-fversion=DubUseCurl',
        '-fversion=DubApplication',
        language: 'd'
    )
endif

curl = dependency('libcurl')

deps = [
    curl
]

subdir('source')

