package require Tcl 8.5
package require http

package require toclbox::log

namespace eval ::toclbox::network {
    namespace eval vars {
    }
    namespace export {[a-z]*}
    namespace import [namespace parent]::log::debug
    namespace ensemble create -command ::toclnet
}


# ::toclbox::network::https -- Backwards-compatible HTTPS support
#
#       This procedure arranges for modern, but backwards compatible, support
#       for HTTPS. It registers ::tls::socket (or a wrapper) for performing
#       HTTPS operations whenever the TLS package is found. The procedure will
#       arrange to support SNI whenever the version of the tls package supports
#       it, and likewise, will attempt to support a list of modern protocols
#       (banning, by default, old SSL2 and SSL3)
#
# Arguments:
#	protos	List of proto name and if it should be turned on/off
#
# Results:
#       The result of ::http::register, empty list on errors.
#
# Side Effects:
#       None.
proc ::toclbox::network::https { {protos {ssl2 0 ssl3 0 tls1 1 tls1.1 1 tls1.2 1}} } {
    if { [catch {package require tls} ver] == 0 } {
        set cmd [list ::tls::socket]

        # First detect presence of servername (for SNI) and re-route to internal
        # command triggering SNI if relevant.
        if { [catch {::tls::socket -servername "toclbox" localhost 0} err] } {
            if { [string match "couldn't open socket*" $err] } {
                set cmd [list [namespace current]::SecureSocket]
            }
        }
        
        # Now detect which of the requested protocols are actually available.
        foreach {opt dft} $protos {
            if { [catch {::tls::socket -$opt 1 localhost 0} err] } {
                 if { [string match "couldn't open socket*" $err] } {
                     lappend cmd -$opt $dft
                 }
            }
        }
        
        debug INFO "Using $cmd for establishing HTTPS connections"
        return [::http::register https 443 $cmd]
    }
    
    return [list]
}


# ::toclbox::network::SecureSocket -- Open a TLS socket
#
#       Open a TLS socket using SNI, i.e. by injecting the name of the remote
#       host to which connection is requested to the TLS package.
#
# Arguments:
#	args	Same as arguments to ::tls::socket
#
# Results:
#       A socket to the server
#
# Side Effects:
#       None.
proc ::toclbox::network::SecureSocket { args } {
    set opts [lrange $args 0 end-2]
    set host [lindex $args end-1]
    set port [lindex $args end]
    return [::tls::socket -servername $host {*}$opts $host $port]
}

package provide toclbox::network 0.1
