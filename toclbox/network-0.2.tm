package require Tcl 8.5
package require http

package require toclbox::log
package require toclbox::url
package require toclbox::text
package require toclbox::options

namespace eval ::toclbox::network {
    namespace eval vars {
        variable tls_socket -;    # Actively discovered TLS socket command
        variable -resolution on
        variable -protos {ssl2 0 ssl3 0 tls1 1 tls1.1 1 tls1.2 1}
        variable -redirects 20;   # Maximum number of redirects that we follow (negative for infinite)
    }
    namespace export {[a-z]*}
    namespace import [namespace parent]::log::debug
    namespace import [namespace parent]::text::resolve
    namespace ensemble create -command ::toclnet
}


proc ::toclbox::network::tls_socket { {protos {}} } {
    # We have a cache and are requesting the default set of protos, return the
    # value of the cache!
    if { [llength $protos] == 0 && $vars::tls_socket ne "-" } {
        return $vars::tls_socket
    }

    # Initialise which TLS protocols to query TLS implementation for
    set reqprotos $protos
    if { [llength $protos] == 0 } { set protos ${vars::-protos} }

    # Build TLS socket command, make sure to cover SNI and actively test the
    # protocols.
    set cmd [list]
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

        debug INFO "Using $cmd for establishing TLS connections"
    } else {
        debug WARN "No TLS package available for secured connections!"
    }

    # Cache information if relevant.
    if { [llength $reqprotos] == 0 } {
        set vars::tls_socket $cmd
    }

    return $cmd
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
proc ::toclbox::network::https { {protos {}} } {
    set cmd [tls_socket $protos]
    if { [llength $cmd] } {
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


# ::toclbox::network::geturl -- Poor man's geturl
#
#       This is an oversimplified version of ::uri::geturl that can arrange for
#       getting the content of files or http resources. It defaults to
#       understand the url passed as a parameter as local file that understands
#       sugarized string (see ::toclbox::text::resolve). This understanding and
#       resolution mechanisms can be turned off by setting the boolean namespace
#       variable -resolution to off. Unknown schemes are not recognised and will
#       return an error. Arguments passed to this procedure are passed further
#       to the relevant content fetch subsystem. For files (file://) this will
#       be the opening mode (e.g. RDONLY BINARY), for http resources this will
#       be arguments to ::http::geturl, for non-URLs this will be a list extra
#       tokens for resolution. Note that this procedure is able to convert
#       authentication data in URLs into basic HTTP authentication.
#
# Arguments:
#	url	Scheme-led URL or file specification
#	args	Blind list of arguments passed to underlying content get.
#
# Results:
#       The content of the file or URL, or an error for unrecognised schemes.
#
# Side Effects:
#       None.
proc ::toclbox::network::geturl { url args } {
    set content ""
    if { [regexp -- {^([\w-]+)://(.*)} $url -> scheme spec] } {
        switch -- $scheme {
            "http" -
            "https" {
                set content [GetHTTP $url {*}$args]
            }
            "file" {
                set content [GetFile $spec {*}$args]
            }
            default {
                return -code error "$scheme is not a supported URL scheme"
            }
        }
    } elseif { ${vars::-resolution} }  {
        # Default to getting it as a file, pass the arguments as extra keys for
        # resolution.
        set content [GetFile [resolve $url $args]]
    }
    
    return $content
}


# ::toclbox::network::GetHTTP -- Get remote HTTP resource
#
#       Wrapper around ::http::geturl that provides supports for basic
#       authentication when user and password are present in URL.
#
# Arguments:
#	url	URL to get data from
#	args	Arguments to ::http::geturl
#
# Results:
#       Content of URL, or an empty string.
#
# Side Effects:
#       Will log errors.
proc ::toclbox::network::GetHTTP { url args } {
    ::toclbox::options::parse args -headers \
            -value hdrs \
            -default [list]
    set surl [::toclbox::url::split $url]
    if { [dict exists $surl user] && [dict get $surl user] ne "" } {
        debug INFO "Adding basic authentication for $user"
        set auth [dict get $surl user]
        if { [dict exists $surl pwd] && [dict get $surl pwd] ne "" } {
            append auth ":[dict get $surl pwd]"
        }
        
        # Prefer 8.6 implementation, otherwise our own...
        if { [catch {binary encode base64 $auth} b64] == 0 } {
            lappend hdrs Authorization "Basic $b64"
        } else {
            lappend hdrs Authorization "Basic [B64en $auth]"
        }
    }
    lappend args -headers $hdrs;  # Keep auth all calls to geturl below...

    for { set i 0 } \
        { ${vars::-redirects} < 0 \
            || (${vars::-redirects} >= 0 && $i < ${vars::-redirects}) } \
        {incr i} {
    
        if { [catch {::http::geturl $url -headers $hdrs {*}$args} tok] == 0} {
            switch -glob -- [::http::ncode $tok] {
                2[0-9][0-9] {
                    set content [::http::data $tok]
                    debug NOTICE "Fetched content of $url via HTTP, ([string length $content] byte(s))"
                    ::http::cleanup $tok
                    return $content
                }
                30[1237] {
                    foreach {k v} [::http::meta $tok] {
                        dict set meta [string tolower $k] $v
                    }
                    if { [dict exists $meta location] && [dict get $meta location] ne "" } {
                        set tgt [::toclbox::url::split [dict get $meta location]]
                        unset meta
                        if { [dict get $tgt host] eq "" } {
                            set src [::toclbox::url::split $url]
                            dict set tgt host [dict get $src host]
                        }
                        set url [::toclbox::url::join {*}$tgt]
                    } else {
                        debug WARN "Could not fetch content of $url via HTTP: [::http::code $tok], [::http::error $tok]"
                        ::http::cleanup $tok
                        return ""        
                    }
                }
                default {
                    debug WARN "Could not fetch content of $url via HTTP: [::http::code $tok], [::http::error $tok]"
                    ::http::cleanup $tok
                    return ""        
                }
            }
            ::http::cleanup $tok
        } else {
            debug WARN "Error when trying to fetch content of $url via HTTP: $tok"
        }
    }
}


# ::toclbox::network::GetFile -- Get file content
#
#       Get content of file
#
# Arguments:
#	fpath	Path to file
#	access	Access for open call, i.e. string or list of rights
#
# Results:
#       Return content of file if we could open it or an error.
#
# Side Effects:
#       Will log errors
proc ::toclbox::network::GetFile { fpath {access "r"} } {
    set content ""
    if { [catch {open $fpath $access} fd] == 0 } {
        debug NOTICE "Got content of local file at $fpath ([string length $content] byte(s))"
        set content [read $fd]
        close $fd
    } else {
        debug WARN "Error getting content of file $fpath: $fd"
    }
    
    return $content
}


# ::toclbox::network::B64en -- Base64 encode
#
#       Simplistic base64 encoding procedure taken from http://wiki.tcl.tk/775.
#       This implementation does not take care of line breaks.
#
# Arguments:
#	str	Input string
#
# Results:
#       The base64 encoded string
#
# Side Effects:
#       None.
proc ::toclbox::network::B64en {str} {
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
