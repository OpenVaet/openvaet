#!/usr/bin/perl

package session;

use strict;
use warnings;
use v5.14;
no autovivification;

sub session_from_self {
    my ($self)        = @_;
    my $referrer      = $self->req->headers->referrer;
    my $ipAddress     = $self->remote_addr;
    # say "referrer  : $referrer";
    # say "ipAddress : $ipAddress";

    my $tb = $self->dbh->selectrow_hashref("SELECT id FROM session WHERE ipAddress = ?", undef, $ipAddress);
    unless ($tb) {
        my $sth = $self->dbh->prepare("INSERT INTO session (ipAddress) VALUES (?)");
        $sth->execute($ipAddress) or die $sth->err();
    }
}

1;