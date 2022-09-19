#!/usr/bin/perl
use strict;
use warnings;
use 5.30.0;
binmode STDOUT, ":utf8";
use utf8;

# Cpan dependencies.
no autovivification;
use Data::Printer;
use Data::Dumper;
use JSON;
use HTTP::Cookies;
use HTML::Tree;
use LWP::UserAgent;
use LWP::Simple;
use File::Path qw(make_path);
use HTTP::Cookies qw();
use HTTP::Request::Common qw(POST OPTIONS);
use HTTP::Headers;
use Hash::Merge;
use Scalar::Util qw(looks_like_number);
use Digest::MD5  qw(md5 md5_hex md5_base64);

# Project's libraries.
use FindBin;
use lib "$FindBin::Bin/../../lib";
use time;
use global;
use country;

my %countryStates = ();
my $latestCountryStateId = 0;
country_states();
my $usCountryName = 'United States of America';
my $usCountryId   = country::country_id_from_name($dbh, $usCountryName);
my $statesFile  = "tasks/cdc/states.csv";      # File containing CDC's states.

my %statesCodes = ();
parse_states();

cdc_states();

sub country_states {
	my $tb = $dbh->selectall_hashref("SELECT id as countryStateId, name as countryStateName FROM country_state WHERE id > $latestCountryStateId", 'countryStateId');
	for my $countryStateId (sort{$a <=> $b} keys %$tb) {
		$latestCountryStateId = $countryStateId;
		my $countryStateName = %$tb{$countryStateId}->{'countryStateName'} // die;
		$countryStates{$countryStateName}->{'countryStateId'} = $countryStateId;
	}
}

sub parse_states {
	open my $in, '<:utf8', $statesFile;
	while (<$in>) {
		chomp $_;
		my ($sNum, $sCode2, $sName) = split ';', $_;
		die if exists $statesCodes{$sCode2};
		$statesCodes{$sNum}->{'stateName'}  = $sName;
		$statesCodes{$sNum}->{'sCode2'} = $sCode2;
	}
	close $in;
}

sub cdc_states {
	my $tb = $dbh->selectall_hashref("SELECT id as cdcStateId, internalId as cdcStateInternalId, name as cdcStateName FROM cdc_state", 'cdcStateId');
	for my $cdcStateId (sort{$a <=> $b} keys %$tb) {
		my $cdcStateInternalId = %$tb{$cdcStateId}->{'cdcStateInternalId'}   // die;
		my $cdcStateName       = %$tb{$cdcStateId}->{'cdcStateName'} // die;
		say "cdcStateInternalId : $cdcStateInternalId";
		say "cdcStateName       : $cdcStateName";
		my $alphaCode2 = $statesCodes{$cdcStateInternalId}->{'sCode2'};
		say "alphaCode2         : $alphaCode2";
		p$statesCodes{$cdcStateInternalId};
		unless (exists $countryStates{$cdcStateName}->{'countryStateId'}) {
			my $sth = $dbh->prepare("INSERT INTO country_state (countryId, name, cdcCode2, alphaCode2) VALUES ($usCountryId, ?, ?, ?)");
			$sth->execute($cdcStateName, $cdcStateInternalId, $alphaCode2) or die $sth->err();
			country_states();
		}
		# die;
	}
}

say "usCountryId : $usCountryId";