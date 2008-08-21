package perfSONAR_PS::Utils::Daemon;

=head1 NAME

perfSONAR_PS::Utils::DNS - A module that provides utility methods for interacting with DNS servers.

=head1 DESCRIPTION

This module provides a set of methods for interacting with DNS servers. This
module IS NOT an object, and the methods can be invoked directly. The methods
need to be explicitly imported to use them.

=head1 DETAILS

The API for this module aims to be simple; note that this is not an object and
each method does not have the 'self knowledge' of variables that may travel
between functions.

=head1 API

The API of perfSONAR_PS::Utils::DNS provides a simple set of functions for
interacting with DNS servers.
=cut

use base 'Exporter';

use strict;
use warnings;

use POSIX qw(setsid);
use Fcntl qw(:DEFAULT :flock);
use File::Basename;

our @EXPORT_OK = ( 'daemonize', 'setids', 'lockPIDFile', 'unlockPIDFile' );

=head2 daemonize({ DEVNULL => /path/to/dev/null, UMASK => $umask, KEEPSTDERR => 1 })
    Causes the calling application to daemonize. The calling application can
    specify what file the child should send its output/receive its input from,
    what the umask for the daemonized process will be and whether or not stderr
    should be redirected to the same location as stdout or if it should keep
    going to the screen. Returns (0, "") on success and (-1, $error_msg) on failure.
=cut

sub daemonize {
    my (%args) = @_;
    my ( $dnull, $umask ) = ( '/dev/null', 022 );

    $dnull = $args{'DEVNULL'} if ( defined $args{'DEVNULL'} );
    $umask = $args{'UMASK'}   if ( defined $args{'UMASK'} );

    my ( $STDIN, $STDOUT, $STDERR );

    open $STDIN,  "<",  "$dnull" or return ( -1, "Can't read $dnull: $!" );
    open $STDOUT, ">>", "$dnull" or return ( -1, "Can't write $dnull: $!" );
    if ( !$args{'KEEPSTDERR'} ) {
        open $STDERR, ">>", "$dnull" or return ( -1, "Can't write $dnull: $!" );
    }

    defined( my $pid = fork ) or return ( -1, "Can't fork: $!" );

    # parent
    exit if $pid;

    setsid or return ( -1, "Can't start new session: $!" );
    umask $umask;

    return ( 0, "" );
}

=head2 setids
    Sets the user/group for an application to run as. Returns 0 on success and
    -1 on failure.
=cut

sub setids {
    my (%args) = @_;
    my ( $uid,  $gid );
    my ( $unam, $gnam );

    $uid = $args{'USER'}  if ( defined $args{'USER'} );
    $gid = $args{'GROUP'} if ( defined $args{'GROUP'} );

    if ( not $uid ) {
        return -1;
    }

    # Don't do anything if we are not running as root.
    return if ( $> != 0 );

    # set GID first to ensure we still have permissions to.
    if ( defined($gid) ) {
        if ( $gid =~ /\D/ ) {

            # If there are any non-digits, it is a groupname.
            $gid = getgrnam( $gnam = $gid );
            if ( not $gid ) {

                #                $logger->error("Can't getgrnam($gnam): $!");
                return -1;
            }
        }
        elsif ( $gid < 0 ) {
            $gid = -$gid;
        }

        if ( not getgrgid($gid) ) {

            #            $logger->error("Invalid GID: $gid");
            return -1;
        }

        $) = $( = $gid;
    }

    # Now set UID
    if ( $uid =~ /\D/ ) {

        # If there are any non-digits, it is a username.
        $uid = getpwnam( $unam = $uid );
        if ( not $uid ) {

            #            $logger->error("Can't getpwnam($unam): $!");
            return -1;
        }
    }
    elsif ( $uid < 0 ) {
        $uid = -$uid;
    }

    if ( not getpwuid($uid) ) {

        #        $logger->error("Invalid UID: $uid");
        return -1;
    }

    $> = $< = $uid;

    return 0;
}

=head2 lockPIDFile($piddir, $pidfile);
The lockPIDFile function checks for the existence of the specified file in
the specified directory. If found, it checks to see if the process in the file
still exists. If there is no running process, it returns the filehandle for the
open pidfile that has been flock(LOCK_EX). Returns (0, "") on success and (-1,
$error_msg) on failure.
=cut

sub lockPIDFile {
    my ($pidfile) = @_;
    return ( -1, "Can't write pidfile: $pidfile" ) unless -w dirname($pidfile);
    sysopen( PIDFILE, $pidfile, O_RDWR | O_CREAT ) or return ( -1, "Couldn't open file: $pidfile" );
    flock( PIDFILE, LOCK_EX );
    my $p_id = <PIDFILE>;
    chomp($p_id) if ( defined $p_id );
    if ( defined $p_id and $p_id ne q{} ) {
        my $PSVIEW;

        open( $PSVIEW, "-|", "ps -p " . $p_id );
        my @output = <$PSVIEW>;
        close($PSVIEW);
        if ( !$? ) {
            return ( -1, "Application is already running on pid: $p_id\n" );
        }
    }

    return ( 0, *PIDFILE );
}

=head2 unlockPIDFile
This file writes the pid of the calling process to the filehandle passed in,
unlocks the file and closes it.
=cut

sub unlockPIDFile {
    my ($filehandle) = @_;

    truncate( $filehandle, 0 );
    seek( $filehandle, 0, 0 );
    print $filehandle "$$\n";
    flock( $filehandle, LOCK_UN );
    close($filehandle);

    return;
}

1;

__END__

=head1 SEE ALSO

L<Exporter>, L<Net::DNS>, L<NetAddr::IP>

To join the 'perfSONAR-PS' mailing list, please visit:

  https://mail.internet2.edu/wws/info/i2-perfsonar

The perfSONAR-PS subversion repository is located at:

  https://svn.internet2.edu/svn/perfSONAR-PS

Questions and comments can be directed to the author, or the mailing list.

=head1 VERSION

$Id$

=head1 AUTHOR

Aaron Brown <aaron@internet2.edu>, Jeff Boote <boote@internet2.edu>

=head1 LICENSE

You should have received a copy of the Internet2 Intellectual Property Framework along
with this software.  If not, see <http://www.internet2.edu/membership/ip.html>

=head1 COPYRIGHT

Copyright (c) 2004-2008, Internet2 and the University of Delaware

All rights reserved.

=cut

# vim: expandtab shiftwidth=4 tabstop=4
