#!/usr/bin/perl
use strict;
use warnings;
use 5.26.0;
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

my $sql = "
    SELECT
        id as reportId,
        breastMilkExposureConfirmation,
        breastMilkExposureConfirmationRequired,
        breastMilkExposureConfirmationTimestamp,
        aEDescription
    FROM report
    WHERE 
        breastMilkExposureConfirmationRequired = 1 AND
        breastMilkExposureConfirmation IS NULL";
my %exclusions = ();
my $tb = $dbh->selectall_hashref($sql, 'reportId');
for my $reportId (sort{$a <=> $b} keys %$tb) {
	my $aEDescription = %$tb{$reportId}->{'aEDescription'} // die;
	my $aEDescriptionNormalized = lc $aEDescription;
	if ($aEDescriptionNormalized =~ /not currently breastfeeding/) {
		$exclusions{'not currently breastfeeding'}++;
		my $sth = $dbh->prepare("UPDATE report SET breastMilkExposureConfirmation = 0, breastMilkExposureConfirmationTimestamp = UNIX_TIMESTAMP(), breastMilkExposureConfirmationUserId = 3 WHERE id = $reportId");
		$sth->execute() or die $sth->err();
		next;
	} elsif ($aEDescriptionNormalized =~ /not pregnant or currently breastfeeding/) {
		$exclusions{'not pregnant or currently breastfeeding'}++;
		my $sth = $dbh->prepare("UPDATE report SET breastMilkExposureConfirmation = 0, breastMilkExposureConfirmationTimestamp = UNIX_TIMESTAMP(), breastMilkExposureConfirmationUserId = 3 WHERE id = $reportId");
		$sth->execute() or die $sth->err();
		next;
	} elsif ($aEDescriptionNormalized =~ /not breastfeeding/) {
		$exclusions{'not breastfeeding'}++;
		my $sth = $dbh->prepare("UPDATE report SET breastMilkExposureConfirmation = 0, breastMilkExposureConfirmationTimestamp = UNIX_TIMESTAMP(), breastMilkExposureConfirmationUserId = 3 WHERE id = $reportId");
		$sth->execute() or die $sth->err();
		next;
	}
}
p%exclusions;

