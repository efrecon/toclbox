package require Tcl 8.5
package require http

package require toclbox::log
package require toclbox::options

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


proc ::toclbox::network::geturl { url args } {
    set content ""
    if { [regexp -- {^([\w-]+)://(.*)} $url -> scheme spec] } {
        switch -- $scheme {
            "http" -
            "https" {
                set URLmatcher {(?x)		# this is _expanded_ syntax
                    ^
                    (?: ([\w-]+) : ) ?		# <protocol scheme>
                    (?: //
                        (?:
                            (
                                [^@/\#?]+		# <userinfo part of authority>
                            ) @
                        )?
                        (				# <host part of authority>
                            [^/:\#?]+ |		# host name or IPv4 address
                            \[ [^/\#?]+ \]		# IPv6 address in square brackets
                        )
                        (?: : (\d+) )?		# <port part of authority>
                    )?
                    ( [/\?] [^\#]*)?		# <path> (including query)
                    (?: \# (.*) )?			# <fragment>
                    $
                }
            
                # Phase one: parse
                ::toclbox::options::parse args -headers \
                        -value hdrs \
                        -default [list]
                if {![regexp -- $URLmatcher $url -> proto user host port srvurl]} {
                    if { $user ne "" } {
                        # Prefer 8.6 implementation, otherwise our own...
                        if { [catch {binary encode base64 $user} b64] == 0 } {
                            lappend hdrs Authorization "Basic $b64"
                        } else {
                            lappend hdrs Authorization "Basic [B64en $user]"
                        }
                    }
                }
                if { [catch {::http::geturl $url -headers $hdrs {*}$args} tok] == 0} {
                    if { [::http::ncode $tok] >= 200 && [::http::ncode $tok] < 300 } {
                        set content [::http::data $tok]
                    }
                    ::http::cleanup $tok
                }
            }
            "file" {
                set content [GetFile $spec {*}$args]
            }
            default {
                return -code error "$scheme is not a supported URL scheme"
            }
        }
    } else {
        # Default to getting it as a file
        set content [GetFile $url {*}$args]
    }
    
    return $content
}


proc ::toclbox::network::GetFile { fpath {access "r"} } {
    set content ""
    if { [catch {open $fpath $access} fd] == 0 } {
        set content [read $fd]
        close $fd
    }
    return $content
}


proc ::toclbox::network::B64en {str} {
    # From http://wiki.tcl.tk/775
    binary scan $str B* bits
    switch [expr {[string length $bits]%6}] {
        0 {set tail {}}
        2 {append bits 0000; set tail ==}
        4 {append bits 00; set tail =}
    }
    return [string map {
        000000 A 000001 B 000010 C 000011 D 000100 E 000101 F
        000110 G 000111 H 001000 I 001001 J 001010 K 001011 L
        001100 M 001101 N 001110 O 001111 P 010000 Q 010001 R
        010010 S 010011 T 010100 U 010101 V 010110 W 010111 X
        011000 Y 011001 Z 011010 a 011011 b 011100 c 011101 d
        011110 e 011111 f 100000 g 100001 h 100010 i 100011 j
        100100 k 100101 l 100110 m 100111 n 101000 o 101001 p
        101010 q 101011 r 101100 s 101101 t 101110 u 101111 v
        110000 w 110001 x 110010 y 110011 z 110100 0 110101 1
        110110 2 110111 3 111000 4 111001 5 111010 6 111011 7
        111100 8 111101 9 111110 + 111111 /
    } $bits]$tail    
}

package provide toclbox::network 0.1
