package require Tcl 8.6;  # Necessary for chan pipe
package require platform

package require toclbox::log

namespace eval ::toclbox::exec {
    namespace eval command {};  # This will host all commands information
    namespace eval vars {
        variable signalling 0; # Forward signals (need Tclx see require below)
        variable generator 0;  # Generator for identifiers, own implementation to keep order
    }
    namespace export {[a-z]*}
    namespace import [namespace parent]::log::debug
    namespace import [namespace parent]::options::parse
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
proc ::toclbox::exec::LineRead { c fd } {
    upvar \#0 $c CMD

    set line [gets $CMD($fd)]

    # Respect -keepblanks and output or accumulate in result
    if { ( !$CMD(keep) && [string trim $line] ne "") || $CMD(keep) } {
	if { $CMD(back) } {
	    if { ( $CMD(outerr) && $fd eq "stderr" ) || $fd eq "stdout" } {
		lappend CMD(result) $line
	    }
	} elseif { $CMD(relay) } {
	    puts $fd $line
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
	if { ( $CMD(stdout) eq "" || [fileevent $CMD(stdout) readable] eq "" ) \
		 && ( $CMD(stderr) eq "" || [fileevent $CMD(stderr) readable] eq "" ) } {
	    set CMD(done) 1
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


proc ::toclbox::exec::run { args } {
    # Isolate -- that will separate options to procedure from options
    # that would be for command.  Using -- is MANDATORY if you want to
    # specify options to the procedure.
    set sep [lsearch $args "--"]
    if { $sep >= 0 } {
        set opts [lrange $args 0 [expr {$sep-1}]]
        set args [lrange $args [expr {$sep+1}] end]
    } else {
        set opts [list]
    }

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
    parse opts -capture CMD(capture) ""
    set CMD(done) 0
    set CMD(result) {}

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
        fileevent $CMD(stdout) readable [namespace code [list LineRead $c stdout]]
    } else {
        lassign [POpen4 {*}$args] CMD(pid) CMD(stdin) CMD(stdout) CMD(stderr)
        fileevent $CMD(stdout) readable [namespace code [list LineRead $c stdout]]
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
    vwait ${c}(done);   # Wait for command to end

    debug TRACE "Command $CMD(command) has ended, cleaning up and returning"
    catch {close $CMD(stdin)}
    catch {close $CMD(stdout)}
    catch {close $CMD(stderr)}

    set res $CMD(result)
    unset $c
    return $res
}


package provide toclbox::exec 1.0