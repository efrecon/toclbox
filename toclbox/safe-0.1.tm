##################
## Module Name     --  safe.tcl
## Original Author --  Emmanuel Frecon - emmanuel.frecon@myjoice.com
## Description:
##
##      Package to a allow a safe interpreter to access islands of the
##      filesystem only, i.e. restricted directory trees within the
##      filesystem. The package brings back file, open and glob to the slave
##      interpreter, though in a restricted manner.
##
##################

package require Tcl 8.5

package require toclbox::log

namespace eval ::toclbox::safe {
    namespace eval interps {};   # Will host information for interpreters
    namespace export {[a-z]*};   # Convention: export all lowercase 
    namespace eval vars {
        variable version       [lindex [split [file rootname [file tail [info script]]] -] end]
    }
    namespace import [namespace parent]::log::debug
    namespace ensemble create -command ::toclsafe
}


# ::toclbox::safe::invoke -- Expose back a command
#
#       This procedure allows to callback a command that would typically have
#       been hidden from a slave interpreter. It does not "interp expose" but
#       rather calls the hidden command, so we can easily revert back. The
#       procedure is aware of the aliases that have been made and stored through
#       alias (see below)
#
# Arguments:
#	slave	Identifier of the slave under our control
#	cmd 	Hidden command to call
#	args	Command to call
#
# Results:
#       As of the hidden command to call
#
# Side Effects:
#       As of the hidden command to call
proc ::toclbox::safe::invoke { slave cmd args } {
    set vname [Context $slave]
    upvar \#0 $vname context

    if { [info exists $vname] && [dict exists $context $cmd] } {
        # Aliased command is to be called in same interpreter as the the main
        # interpreter
        return [uplevel [dict get $context $cmd] $args]
    } elseif { $slave eq "" } {
        return [uplevel [linsert $args 0 $cmd]]
    } else {
        return [uplevel [linsert $args 0 $slave invokehidden $cmd]]
    }
}


# ::toclbox::safe::alias -- Careful aliasing
#
#       Create an alias to an existing into this library, making sure to
#       remember where the command was already aliased to whenever relevant.
#
# Arguments:
#	slave	Identifier of the slave to control
#	cmd 	Command to alias
#	args	Destination command to alias to
#
# Results:
#       None.
#
# Side Effects:
#       None.
proc ::toclbox::safe::alias { slave cmd args } {
    set vname [Context $slave]
    upvar \#0 $vname context

    if { ![info exists $vname] || ![dict exists $context $cmd] } {
        set alias [$slave alias $cmd]
        if { $alias ne "" } {
            dict set context $cmd $alias
        }
    }
    debug DEBUG "Aliased $cmd to $args in $slave"
    return [uplevel [linsert $args 0 $slave alias $cmd]]
}


# ::toclbox::safe::unalias -- Remove alias
#
#       Remove an alias, reverting it to which ever command it was aliased to,
#       meaning removing the alias entirely whenever relevant.
#
# Arguments:
#	slave	Identifier of the slave to control
#	cmd 	Command to unalias
#
# Results:
#       None.
#
# Side Effects:
#       None.
proc ::toclbox::safe::unalias { slave cmd } {
    set vname [Context $slave]
    if { [info exists $vname] } {
        upvar \#0 $vname context
        if { [dict exists $context $cmd] } {
            debug DEBUG "Reverting back $cmd to [dict get $context $cmd] in $slave"
            $slave alias $cmd [dict get $context $cmd]
        }
        unset $vname
    } else {
        debug DEBUG "Unaliasing $cmd in $slave"
        $slave alias $cmd {}
    }
}

proc ::toclbox::safe::environment { slave {allow *} {deny {}} {glbl env}} {
    debug NOTICE "Selectively passing keys matching $allow (but not $deny) from global $glbl"
    upvar \#0 $glbl var
    foreach varname [array names var] {
        if { [Allowed $varname $allow $deny] } {
            debug DEBUG "Passing $varname to $glbl in slave"
            $slave eval [list set ::${glbl}($varname) $var($varname)]
        }
    }
}

proc ::toclbox::safe::envset { slave varname {value ""} {glbl env}} {
    debug NOTICE "Setting $varname in global $glbl"
    $slave eval [list set ::${glbl}($varname) $value]
}

proc ::toclbox::safe::package { slave pkg { version ""} } {
    set pver [expr {$version eq "" ? $pkg : "${pkg}:${version}"}]
    if { [$slave issafe] } {
        if { [catch {::safe::interpConfigure $slave} res] } {
            debug NOTICE "Loading $pver into safe slave"
            set cmds [LoadCommand $pkg $version]
            foreach l [split $cmds ";\r\n"] {
                switch -- [lindex $l 0] {
                    "source" {
                        debug INFO "Sourcing [lindex $l end] to bring in package $pkg"
                        eval [linsert $l 0 $slave invokehidden -global --]
                    }
                    "load" {
                        debug INFO "Loading binary [lindex $l end] to bring in package $pkg"
                        eval [linsert $l 0 $slave invokehidden -global --]
                    }
                    default {
                        $slave eval $l
                    }
                }
            }
        } else {
            debug NOTICE "Loading $pver into Safe-Tcl slave"
            if { $version ne "" } {
                $slave eval package require $pkg $version
            } else {
                $slave eval package require $pkg
            }
        }
    } else {
        debug NOTICE "Loading $pver into regular slave"
        if { $version ne "" } {
            $slave eval package require $pkg $version
        } else {
            $slave eval package require $pkg
        }
    }
}


# ::toclbox::safe::OutsideCaller -- First caller out of this namespace
#
#       Return the first calling procedure in the stack that is known to be
#       outside of this namespace.
#
# Arguments:
#       None.
#
# Results:
#       Return the fully qualified name of the procedure (or :: for the toplevel
#       context)
#
# Side Effects:
#       None.
proc ::toclbox::safe::OutsideCaller {} {
    for {set i [info level]} {$i > 0} { incr i -1 } {
        set caller [namespace which -command [lindex [info level $i] 0]]
        set fqns [namespace qualifiers $caller]
        if { $fqns ne "" && $fqns ne [namespace current] } {
            return $caller
        }
    }
    return "::";  # Failsafe toplevel
}


# ::toclbox::safe::Context -- Create storage context
#
#       Create unique name in children namespace, based on both the interpreter,
#       but also the calling namespace so as to cover multiple aliasing from
#       several namespaces.
#
# Arguments:
#	slave	Identifier of the slave
#
# Results:
#       Error or a string into our sub-namespace used for storage.
#
# Side Effects:
#       None.
proc ::toclbox::safe::Context { slave } {
    set origin [OutsideCaller]
    if { $origin eq "" } {
        return -code error "Cannot find origin caller"
    }
    
    return [namespace current]::interps::[string map {: _} [namespace qualifiers $origin]]__[string map {: _} $slave]
}


proc ::toclbox::safe::Allowed { key allow deny } {
    set allowed 0;  # Default is to deny everything!
    foreach ptn $allow {
        if { [string match $ptn $key] } {
            set allowed 1
            break
        }
    }
    if { $allowed  } {
        foreach ptn $deny {
            if { [string match $ptn $key] } {
                set allowed 0
                break
            }
        }
    }
    return $allowed
}


proc ::toclbox::safe::LoadCommand {name {version ""}} {
    # Get the command to load a package without actually loading the package
    #
    # package ifneeded can return us the command to load a package but
    # it needs a version number. package versions will give us that
    set versions [::package versions $name]
    if {[llength $versions] == 0} {
        # We do not know about this package yet. Invoke package unknown
        # to search
        {*}[::package unknown] $name
        # Check again if we found anything
        set versions [::package versions $name]
        if {[llength $versions] == 0} {
            error "Could not find package $name"
        }
    }

    # Pick latest version when none specified.
    if { $version eq "" } {
        foreach v $versions {
            if { $version eq "" || [::package vcompare $v $version] > 0 } {
                set version $v
            }
        }
        debug DEBUG "Amongst $versions, latest version for $name is $version"
    }
    return [::package ifneeded $name $version]
}

package provide toclbox::safe $::toclbox::safe::vars::version