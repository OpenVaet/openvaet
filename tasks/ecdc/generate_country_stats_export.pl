#!/usr/bin/perl
use strict;
use warnings;
use 5.30.0;
no autovivification;
binmode STDOUT, ":utf8";
use utf8;
use Data::Printer;
use Data::Dumper;
use JSON;
use Scalar::Util qw(looks_like_number);
use FindBin;
use lib "$FindBin::Bin/../../lib";

# Project's libraries.
use global;
use time;

my %countries = ();

countries();
drugs();

sub countries {
	my $tb = $dbh->selectall_hashref("SELECT id as countryId, name as countryName FROM ecdc_country", 'countryId');
	for my $countryId (sort{$a <=> $b} keys %$tb) {
		my $countryName = %$tb{$countryId}->{'countryName'} // die;
		$countries{$countryId}->{'countryName'} = $countryName;
	}
}

sub drugs {
	open my $outCountry, '>:utf8', 'statistics_by_countries.csv';
	say $outCountry "drugName;countryName;totalEvents;";
	my $tb = $dbh->selectall_hashref("SELECT id as drugId, internalId as eudraVigilanceInternalId, url as drugUrl, overviewStats, name as drugName FROM ecdc_drug", 'drugId');
	for my $drugId (sort{$a <=> $b} keys %$tb) {
		my $drugName = %$tb{$drugId}->{'drugName'} // die;
		next unless $drugName =~ /COVID/;
		say "*" x 50;
		say "drugName : $drugName";
		say "*" x 50;
		my $eudraVigilanceInternalId = %$tb{$drugId}->{'eudraVigilanceInternalId'} // die;
		my $drugUrl = %$tb{$drugId}->{'drugUrl'} // die;
		my $overviewStats = %$tb{$drugId}->{'overviewStats'} // die;
		$overviewStats = decode_json($overviewStats);
		my %overviewStats = %$overviewStats;
		for my $countryId (sort keys %{$overviewStats{'byCountry'}}) {
			my $countryName = $countries{$countryId}->{'countryName'} // die;
			my $totalEvents = $overviewStats{'byCountry'}->{$countryId} // die;
			say "countryName : $countryName";
			say "totalEvents : $totalEvents";
			say $outCountry "$drugName;$countryName;$totalEvents;";
		}
		# p$overviewStats;
		# die;
	}
	close $outCountry;
}
