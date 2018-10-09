package require Tcl 8.6;  # Necessary for chan pipe
package require platform

package require toclbox::log
package require toclbox::options
package require toclbox::config
package require toclbox::control

namespace eval ::toclbox::exec {
    namespace eval command {};  # This will host all commands information
    namespace eval vars {
        variable -bufsize   16384
        variable signalling 0;  # Forward signals (need Tclx see require below)
        variable generator  0;  # Generator for identifiers, own implementation to keep order
        variable armor      {}; # AppArmor bin execution restrictions
        variable renamed    0;  # Hijacked open/exec calls?
        variable version    [lindex [split [file rootname [file tail [info script]]] -] end]
    }
    namespace export {[a-z]*}
    namespace import [namespace parent]::log::debug
    namespace import [namespace parent]::options::parse
    namespace import [namespace parent]::options::pull
    namespace ensemble create -command ::toclexec
}

# Load Tclx whenever available to properly forward signals (if possible)
if { [catch {package require Tclx} ver] == 0 } {
    ::toclbox::exec::debug INFO "Will properly forward signals using Tclx v $ver"
    set ::toclbox::exec::vars::signalling 1
}

# ::POpen4 -- Pipe open
#
#       This procedure executes an external command and arranges to
#       redirect locally assiged channel descriptors to its stdin,
#       stdout and stderr.  This makes it possible to send input to
#       the command, but also to properly separate its two forms of
#       outputs.
#
# Arguments:
#	args	Command to execute
#
# Results:
#       A list of four elements.  Respectively: the list of process
#       identifiers for the command(s) that were piped, channel for
#       input to command pipe, for regular output of command pipe and
#       channel for errors of command pipe.
#
# Side Effects:
#       None.
proc ::toclbox::exec::POpen4 { args } {
    foreach chan {In Out Err} {
        lassign [chan pipe] read$chan write$chan
    } 

    set pid [exec {*}$args <@ $readIn >@ $writeOut 2>@ $writeErr &]
    chan close $readIn
    chan close $writeOut
    chan close $writeErr

    foreach chan [list stdout stderr $readOut $readErr $writeIn] {
        chan configure $chan -buffering line -blocking false
    }
    
    return [list $pid $writeIn $readOut $readErr]
}


# ::LineRead -- Read line output from started commands
#
#       This reads the output from commands that we have started, line
#       by line and either prints it out or accumulate the result.
#       Properly mark for end of output so the caller will stop
#       waiting for output to happen.  When outputing through the
#       logging facility, the procedure is able to recognise the
#       output of docker-machine commands (which uses the logrus
#       package) and to convert between loglevels.
#
# Arguments:
#	c	Identifier of command being run
#	fd	Which channel to read (refers to index in command)
#
# Results:
#       None.
#
# Side Effects:
#       Read lines, outputs
proc ::toclbox::exec::LineRead { c fd {chunks -1}} {
    upvar \#0 $c CMD

    if { $chunks < 0 } {
        set line [gets $CMD($fd)]
    } else {
        set line [read $CMD($fd) $chunks]
    }

    # Respect -keepblanks and output or accumulate in result
    if { ( !$CMD(keep) && [string trim $line] ne "") || $CMD(keep) } {
	if { $CMD(back) } {
	    if { ( $CMD(outerr) && $fd eq "stderr" ) || $fd eq "stdout" } {
                if { $chunks < 0 } {
                    lappend CMD(result) $line
                } else {
                    append CMD(result) $line
                }
	    }
	} elseif { $CMD(relay) } {
            if { $chunks < 0 } {
                puts $fd $line
            } else {
                puts -nonewline $fd $line
            }
	}

        if { [llength $CMD(capture)] } {
            if { [catch {eval [linsert $CMD(capture) end $fd $line]} err] } {
                debug WARN "Could not forward line to capturing command: $err"
            }
        }
    }

    # On EOF, we stop this very procedure to be triggered.  If there
    # are no more outputs to listen to, then the process has ended and
    # we are done.
    if { [eof $CMD($fd)] } {
	fileevent $CMD($fd) readable {}
        debug TRACE "EOF reached on $fd"
	if { ( $CMD(stdout) eq "" || [fileevent $CMD(stdout) readable] eq "" ) \
		 && ( $CMD(stderr) eq "" || [fileevent $CMD(stderr) readable] eq "" ) } {
	    set CMD(done) 1
            if { [llength $CMD(finished)] } {
                Done $c
            }
	}
    }
}


# Running commands, ordered by creation time.
proc ::toclbox::exec::running {} {
    return [lsort [info vars [namespace current]::command::*]]
}


proc ::toclbox::exec::Signal { c signal through self } {
    debug NOTICE "Signal $signal received"
    if { $through && [info exists $c] } {
        upvar \#0 $c CMD
        debug DEBUG "Passing signal $signal through to $CMD(pid)"
        catch {::kill $signal $CMD(pid)}
    }

    if { $self } {
        debug DEBUG "Executing default behaviour for $signal on ourselves"
        ::signal default $signal
        catch {::kill $signal [pid]}
        ::signal trap $signal [namespace code [list Signal $c %S $through $self]]
    }
}


proc ::toclbox::exec::Done { c } {
    upvar \#0 $c CMD

    debug TRACE "Command $CMD(command) has ended, cleaning up and returning"
    catch {close $CMD(stdin)}
    catch {close $CMD(stdout)}
    catch {close $CMD(stderr)}

    # Collect and possibly mediate result
    set res $CMD(result)
    if { [llength $CMD(finished)] } {
        if { [catch {eval [linsert $CMD(finished) end $CMD(pid) $res]} err] } {
            debug WARN "Could not forward line to capturing command: $err"
        }
    }
    
    # Total cleanup
    unset $c
    return $res
}


proc ::toclbox::exec::armor { args } {
    if { [llength $args] == 1 } {
        return [apparmor {*}[concat [[namespace parent]::config::read [lindex $args 0] -1 "rules"]]]
    }

    foreach {k v} $args {
        set k [string trimleft $k -]
        switch -glob -nocase -- $k {
            "a*" { lappend vars::armor -allow $v }
            "d*" { lappend vars::armor -deny $v }
            default {
                debug WARN "$k is not a known filter, should be -allow or -deny"
            }
        }
    }

    if { ! $vars::renamed } {
        rename ::exec [namespace current]::ExecOrig
        proc ::exec { args } {
            ::toclbox::exec::ArmorCheck {*}$args
            return [::toclbox::exec::ExecOrig {*}$args]
        }
        
        rename ::open [namespace current]::OpenOrig
        proc ::open { args } {
            if { [string index [lindex $args 0] 0] eq "|" } { 
                ::toclbox::exec::ArmorCheck {*}[lindex $args 0]
            }
            return [::toclbox::exec::OpenOrig {*}$args]
        }
        set vars::renamed 1
    }

    return $vars::armor
}


proc ::toclbox::exec::ArmorCheck { args } {
    # Extract binaries being called from argument list into list called bins.
    set bins [list]
    if { [string index [lindex $args 0] 0] eq "|" } {
        lappend bins [string range [lindex $args 0] 1 end]
    } elseif { [lindex $args 0] ne "|" } {
        lappend bins [lindex $args 0]
    }

    foreach i [lsearch -exact -all $args "|"] {
        lappend bins [lindex $args [expr {$i+1}]]
    }
    debug TRACE "Extracted [join $bins , ] from pipeline"

    # Resolve binaries to their real location on disk and check each in turn if
    # they are allowed by the filters.
    foreach bin $bins {
        # Resolve, including last link
        set rbin [auto_execok $bin]
        if { $rbin eq "" } {
            return -code error "Resolved $bin to empty binary, access forbidden by apparmor"
        }

        set allowed 0
        foreach {k v} $vars::armor {
            if { $k eq "-allow" && [string match $v $rbin] } {
                set allowed 1; break
            }
        }

        if { $allowed } {
            foreach {k v} $vars::armor {
                if { $k eq "-deny" && [string match $v $rbin] } {
                    set allowed 0; break
                }
            }
        }

        if { !$allowed } {
            return -code error "Resolved binary at $rbin is forbidden to access by apparmor"
        }
    }
}


proc ::toclbox::exec::run { args } {
    # Isolate -- that will separate options to procedure from options
    # that would be for command.  Using -- is MANDATORY if you want to
    # specify options to the procedure.
    pull args opts

    # Create an array global to the namespace that we'll use for
    # synchronisation and context storage.
    set c [namespace current]::command::[format %05d [incr vars::generator]]
    upvar \#0 $c CMD
    set CMD(id) $c
    set CMD(command) $args
    debug DEBUG "Executing $CMD(command) and capturing its output"

    # Extract some options and start building the
    # pipe.  As we want to capture output of the command, we will be
    # using the Tcl command "open" with a file path that starts with a
    # "|" sign.
    set CMD(keep) [parse opts -keepblanks]
    set CMD(back) [parse opts -return]
    set CMD(outerr) [parse opts -stderr]
    set CMD(relay) [parse opts -raw]
    set CMD(binary) [parse opts -binary]
    parse opts -capture CMD(capture) [list]
    parse opts -done CMD(finished) [list]
    set CMD(done) 0
    set CMD(result) {}
    if { $CMD(relay) } { set CMD(keep) 1 };   # Force keeping blanks on raw

    # Kick-off the command and wait for its end
    if { [lsearch [split [::platform::generic] -] win32] >= 0 } {
        set pipe |[concat $args]
        if { $CMD(outerr) } {
            append pipe " 2>@1"
        }
        set CMD(stdin) ""
        set CMD(stderr) ""
        set CMD(stdout) [open $pipe]
        set CMD(pid) [pid $CMD(stdout)]
        if { $CMD(binary) } {
            fconfigure $CMD(stdout) -encoding binary -translation binary
            fileevent $CMD(stdout) readable [namespace code [list LineRead $c stdout ${vars::-bufsize}]]
        } else {
            fileevent $CMD(stdout) readable [namespace code [list LineRead $c stdout]]            
        }
    } else {
        lassign [POpen4 {*}$args] CMD(pid) CMD(stdin) CMD(stdout) CMD(stderr)
        if { $CMD(binary) } {
            fconfigure $CMD(stdout) -encoding binary -translation binary
            fileevent $CMD(stdout) readable [namespace code [list LineRead $c stdout ${vars::-bufsize}]]
        } else {
            fileevent $CMD(stdout) readable [namespace code [list LineRead $c stdout]]            
        }
        fileevent $CMD(stderr) readable [namespace code [list LineRead $c stderr]]
    }
    if { $vars::signalling } {
        foreach {signal through self} [list HUP 1 1 INT 1 1 QUIT 1 1 ABRT 1 1 TERM 0 1 CONT 1 1 USR1 1 0 USR2 1 0] {
            if { [catch {signal get $signal} settings] == 0 } {
                ::signal trap $signal [namespace code [list Signal $c %S $through $self]]
            } else {
                debug WARN "Cannot properly handle signal $signal: $settings"
            }
        }
    }
    debug TRACE "Started $CMD(command), running at $CMD(pid)"
    if { [llength $CMD(finished)] } {
        return $CMD(pid)
    } else {
        vwait ${c}(done);   # Wait for command to end

        return [Done $c]    
    }
}


package provide toclbox::exec $::toclbox::exec::vars::version