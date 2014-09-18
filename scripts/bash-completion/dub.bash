# dub(1) completion                                   -*- shell-script -*-

_dub()
{
    local cur prev words cword split
    _init_completion -s || return

    local creation_commands
    creation_commands='init run build test generate describe clean dustmite'

    local management_commands
    management_commands='fetch remove upgrade add-path remove-path add-local remove-local list add-override remove-override list-overrides'

    case "$prev" in
        -h|--help)
            return 0
            ;;
    esac

    $split && return 0

    # Use -h -v -q because lack of comma separation between -h and --help
    local common_options
    common_options='-h -v -q';

    local packages
    packages=$(dub list| awk '/^[[:space:]]+/ { print $1 }')

    if [[ $cword -eq 1 ]] ; then # if one argument given
        if [[ "$cur" == -* ]]; then
            COMPREPLY=( $( compgen -W '$common_options $( _parse_help "$1" )' -- "$cur" ) )
        else
            COMPREPLY=( $( compgen -W "$creation_commands $management_commands" -- "$cur" ) )
        fi
    else
        local command=${words[1]}; # use $prev instead?

        local specific_options
        specific_options=$( "$1" $command --help 2>/dev/null | _parse_help - )

        case $command in
            init | add-path | remove-path | add-local | remove-local | dustmite )
                COMPREPLY=( $( compgen -d -W '$common_options $specific_options' -- "$cur" ) )
                ;;
            run | build | test | generate | describe | clean | upgrade | add-override | remove-override )
                COMPREPLY=( $( compgen -W '$packages $common_options $specific_options' -- "$cur" ) )
                ;;
            *)
                COMPREPLY=( $( compgen -W '$common_options $specific_options' -- "$cur" ) )
                ;;
        esac
    fi

    [[ $COMPREPLY == *= ]] && compopt -o nospace
    return

    # NOTE: Disabled for now
    # _filedir
} &&
complete -F _dub dub
