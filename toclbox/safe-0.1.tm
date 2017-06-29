##################
## Module Name     --  island.tcl
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
    namespace import [namespace parent]::log::debug
    namespace ensemble create -command ::toclsafe
    variable version 0.1
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

package provide toclbox::safe $::toclbox::safe::version