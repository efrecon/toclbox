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
package require toclbox::safe

namespace eval ::toclbox::island {
    namespace eval interps {};   # Will host information for interpreters
    namespace export {[a-z]*};   # Convention: export all lowercase 
    namespace eval vars {
        variable version       [lindex [split [file rootname [file tail [info script]]] -] end]        
    }
    namespace import [namespace parent]::log::debug
    namespace import \
            [namespace parent]::safe::alias \
			[namespace parent]::safe::unalias \
			[namespace parent]::safe::invoke
    namespace ensemble create -command ::toclisland
}


# ::island::add -- Add allowed path
#
#       Add a path to the list of paths that are explicitely allowed for access
#       to a slave interpreter. Access to any path that has not been explicitely
#       allowed will be denied. Paths that are added to the list of allowed
#       islands are always fully normalized.
#
# Arguments:
#	slave	Identifier of the slave to control
#	path	Path to add to allowed list
#
# Results:
#       The current list of allowed path
#
# Side Effects:
#       None.
proc ::toclbox::island::add { slave path } {
    debug notice "Allowing recursive access to $path"
    set vname [namespace current]::interps::[string map {: _} $slave]
    if { ![info exists $vname]} {
        Init $slave
    }
    upvar \#0 $vname context
    dict lappend context paths [::file dirname [::file normalize $path/___]]
}


# ::island::reset -- Cleanup
#
#       Remove all access path allowance and arrange for the interpreter to be
#       able to return to the regular safe state.
#
# Arguments:
#	slave	Identifier of the slave
#
# Results:
#       None.
#
# Side Effects:
#       None.
proc ::toclbox::island::reset { slave } {
    set vname [namespace current]::interps::[string map {: _} $slave]
    if { [info exists $vname]} {
        foreach cmd [list file fconfigure cd glob open] {
            unalias $slave $cmd
        }
    }
}



########################
##
## Procedures below are internal to the implementation.
##
########################


# ::island::Allowed -- Check access restrictions
#
#       Check that the file name passed as an argument is within the islands of
#       the filesystem that have been registered through the add command for a
#       given (safe) interpreter. The path is fully normalized before testing
#       against the islands, which themselves are fully normalized.
#
# Arguments:
#	slave	Identifier of the slave under out control
#	fname	(relative) path to the file to test
#
# Results:
#       1 if access is allowed, 0 otherwise
#
# Side Effects:
#       None.
proc ::toclbox::island::Allowed { slave fname } {
    set vname [namespace current]::interps::[string map {: _} $slave]
    upvar \#0 $vname context

    set abs_fname [::file dirname [::file normalize $fname/___]]
    if { [info exists $vname] && [dict exists $context paths] } {
        foreach path [dict get $context paths] {
            if { [string first $path $abs_fname] == 0 } {
                return 1
            }
        }
    }
    return 0
}


# ::island::File -- Restricted file
#
#       Parses the options and arguments to the file command to discover which
#       paths it tries to access and only return the results of its execution
#       when these path are within the allowed islands of the filesystem.
#
# Arguments:
#	slave	Identifier of the slave under our control
#	cmd	Subcommand of the file command.
#	args	Arguments to the file subcommand.
#
# Results:
#       As of the file command.
#
# Side Effects:
#       As of the file command.
proc ::toclbox::island::File { slave cmd args } {
    switch $cmd {
        atime -
        attributes -
        executable -
        exists -
        isdirectory -
        isfile -
        lstat -
        mtime -
        normalize -
        owned -
        readable -
        readlink -
        size -
        stat -
        system -
        type -
        writable {
            set fname [lindex $args 0]
            if { [Allowed $slave $fname] } {
                return [uplevel [linsert $args 0 [namespace current]::invoke "" ::file $cmd]]
                # file is highly restrictive in slaves, so we can't do the following.
                return [uplevel [linsert $args 0 $slave invokehidden ::file $cmd]]
            } else {
                return -code error "Access to $fname denied."
            }
        }
        channels -
        dirname -
        extension -
        join -
        nativename -
        pathtype -
        rootname -
        separator -
        split -
        tail -
        volumes {
            return [uplevel [linsert $args 0 [namespace current]::invoke "" ::file $cmd]]
            # file is highly restrictive in slaves, so we can't do the following.
            return [uplevel [linsert $args 0 $slave invokehidden file $cmd]]
        }
        copy -
        delete -
        rename -
        link {
            set idx [lsearch $args "--"]
            if { $idx >= 0 } {
                set paths [lrange $args [expr {$idx+1}] end]
            } else {
                if { [string index [lindex $args 0] 0] eq "-" } {
                    set paths [lrange $args 1 end]
                } else {
                    set paths $args
                }
            }
            foreach path $paths {
                if { ![Allowed $slave $path] } {
                    return -code error "Access to $path denied."
                }
            }
            return [uplevel [linsert $args 0 [namespace current]::invoke "" ::file $cmd]]
            # file is highly restrictive in slaves, so we can't do the following.
            return [uplevel [linsert $args 0 $slave invokehidden file $cmd]]
        }
        mkdir {
            foreach path $args {
                if { ![Allowed $slave $path] } {
                    return -code error "Access to $path denied."
                }
            }
            return [uplevel [linsert $args 0 [namespace current]::invoke "" ::file $cmd]]
            # file is highly restrictive in slaves, so we can't do the following.
            return [uplevel [linsert $args 0 $slave invokehidden file $cmd]]
        }
    }
}


# ::island::Open -- Restricted open
#
#       Parses the options and arguments to the open command to discover which
#       paths it tries to access and only return the results of its execution
#       when these path are within the allowed islands of the filesystem.
#
# Arguments:
#	slave	Identifier of the slave under our control
#	args	Arguments to the open command.
#
# Results:
#       As of the open command.
#
# Side Effects:
#       As of the open command.
proc ::toclbox::island::Open { slave args } {
    set fname [lindex $args 0]
    if { [string index [string trim $fname] 0] eq "|" } {
        return -code error "Execution of external programs disabled."
    }
    
    if { [Allowed $slave $fname] } {
        return [uplevel [linsert $args 0 [namespace current]::invoke $slave open]]
    } else {
        return -code error "Access to $fname denied."
    }
}


proc ::toclbox::island::Cd { slave { dirname "" } } {
    if { $dirname eq "" } {
        return [uplevel [list [namespace current]::invoke $slave cd]]
    } else {
        if { ![Allowed $slave $dirname] } {
            return -code error "Access to $dirname denied"
        } else {
            return [uplevel [list [namespace current]::invoke $slave cd $dirname]]            
        }
    }
}

# ::island::Glob -- Restricted glob
#
#       Parses the options and arguments to the glob command to discover which
#       paths it tries to access and only return the results of its execution
#       when these path are within the allowed islands of the filesystem.
#
# Arguments:
#	slave	Identifier of the slave under our control
#	args	Arguments to the glob command.
#
# Results:
#       As of the glob command.
#
# Side Effects:
#       As of the glob command.
proc ::toclbox::island::Glob { slave args } {
    set noargs [list -join -nocomplain -tails]
    set within ""
    for {set i 0} {$i < [llength $args]} {incr i} {
        set itm [lindex $args $i]
        if { $itm eq "--" } {
            incr i; break
        } elseif { [string index $itm 0] eq "-" } {
            # Segragates between options that take a value and options that
            # have no arguments and are booleans.
            if { [lsearch $noargs $itm] < 0 } {
                incr i;  # Jump over argument
                switch -glob -- $itm {
                    "-dir*" {
                        set within [lindex $args $i]
                        append within /
                    }
                    "-path*" {
                        set within [lindex $args $i]
                    }
                }
            }
        } else {
            break
        }
    }

    foreach ptn [lrange $args $i end] {
        set path ${within}$ptn
        if { ![Allowed $slave $path] } {
            return -code error "Access to $path denied."
        }
    }

    return [uplevel [linsert $args 0 [namespace current]::invoke $slave glob]]            
}


# ::island::Init -- Initialise interp
#
#       Initialise slave interpreter so that it will be able to perform some
#       file operations, but only within some islands of the filesystem.
#
# Arguments:
#	slave	Identifier of the slave to control
#
# Results:
#       None.
#
# Side Effects:
#       None.
proc ::toclbox::island::Init { slave } {
    alias $slave file [namespace current]::File $slave
    alias $slave glob [namespace current]::Glob $slave
    # Allow to open some of the files, and since we did, arrange to be able to
    # fconfigure them once opened.
    alias $slave cd [namespace current]::Cd $slave
    alias $slave open [namespace current]::Open $slave
    alias $slave fconfigure [namespace current]::invoke $slave fconfigure
}


package provide toclbox::island $::toclbox::island::vars::version
