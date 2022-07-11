#!/usr/bin/perl
use strict;
use warnings;
use v5.30;
use Data::Dumper;
use Data::Printer;
binmode STDOUT, ":utf8";
use utf8;
use JSON;
use HTTP::Cookies;
use HTML::Tree;
use LWP::UserAgent;
use LWP::Simple;
use FindBin;
use lib "$FindBin::Bin/../../../lib";

# Project's libraries.
use time;

# UA used to scrap target.
my $cookie = HTTP::Cookies->new();
my $ua     = LWP::UserAgent->new
(
    timeout    => 30,
    cookie_jar => $cookie,
    agent      => 'Mozilla/5.0 (Windows NT 6.3; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/77.0.3865.90 Safari/537.36'
);

my %data   = ();

die unless -d "raw_data/libramemoria";

my $fromDatetime = '2007-01-01 12:00:00';
my $toDatetime   = time::current_datetime();
($toDatetime)    = split ' ', $toDatetime;
$toDatetime      = "$toDatetime 12:00:00";

say "Going from [$fromDatetime] to [$toDatetime]";
my $fromTimestamp = time::datetime_to_timestamp($fromDatetime);
my $toTimestamp   = time::datetime_to_timestamp($toDatetime);
my $totalFound    = 0;
while ($fromTimestamp <= $toTimestamp) {
	my ($fromDate) = split ' ', $fromDatetime;
	my $dailyFile  = "raw_data/libramemoria/libramemoria_" . "$fromDate.json";
	my $knownDeaths       = 0;
	unless (-f $dailyFile) {
		my ($fromYear, $fromMonth, $fromDay) = split '-', $fromDate;
		my $pageNum           = 0;
		my $formerKnownDeaths = 1;
		while ($knownDeaths != $formerKnownDeaths) {
			$pageNum++;
			$formerKnownDeaths = $knownDeaths;
			my $url         = "https://www.libramemoria.com/avis?nom=&prenom=&debut=" .
					      "$fromDay%2f$fromMonth%2f$fromYear&fin=$fromDay%2f$fromMonth%2f$fromYear&departement=&commune=&communeName=&titre=&page=$pageNum";

			my $currentDatetime = time::current_datetime();
			say "[$currentDatetime] - Getting date [$fromDatetime] - page [$pageNum] - found [$knownDeaths] -> [$url]";
			my $res = $ua->get($url);
			unless ($res->is_success)
			{
				die "failed to get [$url]";
			}
			my $content = $res->decoded_content;
			my $tree    = HTML::Tree->new();
			$tree->parse($content);
			if ($tree->look_down(class=>"tableau_liste")) {
				my $deaths  = $tree->look_down(class=>"tableau_liste");
				my @deaths  = $deaths->look_down(class=>"ligne");
				for my $death (@deaths) {
					my $name = $death->find('a');
					my $age  = $name->find('span');
					my $url  = $name->attr_get_i('href');
					$name    = $name->as_trimmed_text;
					if ($age) {
						$age  = $age->as_trimmed_text;
						$name =~ s/ \($age\)$//;
					}
					# say $death->as_HTML('<>&', "\t");
					my $city     = $death->look_down(class=>"cellule ville liste_virgule alone");
					unless ($city) {
						$city    = $death->look_down(class=>"cellule ville liste_virgule");
					}
					$city        = $city->find('a');
					my $cityUrl  = $city->attr_get_i('href');
					my $cityName = $city->as_trimmed_text;

					# say "name     : $name";
					# say "age      : $age";
					# say "url      : $url";
					# say "cityName : $cityName";
					# say "cityUrl  : $cityUrl";
					unless ($data{$url}) {
						$knownDeaths++;
						$data{$url}->{'name'}     = $name;
						$data{$url}->{'cityName'} = $cityName;
						$data{$url}->{'cityUrl'}  = $cityUrl;
						$data{$url}->{'age'}      = undef;
					}
					# die;
				}
			} else {
				last;
			}
		}
		say "raw_data/libramemoria/libramemoria_" . "$fromDate.json";
		open my $out, '>:utf8', $dailyFile or die $!;
		print $out encode_json\%data;
		close $out;
		$totalFound      += $knownDeaths;
		say "*" x 50;
		say "On          [$fromDate]";
		say "Found       : $knownDeaths";
		say "Total found : $totalFound";
	}
	$fromDatetime     = time::add_seconds_to_datetime($fromDatetime, 86400);
	$fromTimestamp    = time::datetime_to_timestamp($fromDatetime);
	%data = ();

}