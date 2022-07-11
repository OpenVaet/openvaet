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

my ($date) = @ARGV;
die unless $date;

my $dailyFile  = "raw_data/libramemoria/libramemoria_" . "$date.json";
my $knownDeaths       = 0;
my ($fromYear, $fromMonth, $fromDay) = split '-', $date;
my $pageNum           = 0;
my $formerKnownDeaths = 1;
while ($knownDeaths != $formerKnownDeaths) {
	$pageNum++;
	$formerKnownDeaths = $knownDeaths;
	my $url         = "https://www.libramemoria.com/avis?nom=&prenom=&debut=" .
			      "$fromDay%2f$fromMonth%2f$fromYear&fin=$fromDay%2f$fromMonth%2f$fromYear&departement=&commune=&communeName=&titre=&page=$pageNum";

	my $currentDatetime = time::current_datetime();
	# say "[$currentDatetime] - Getting date [$datetime] - page [$pageNum] - found [$knownDeaths] -> [$url]";
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
			my $deathUrl = $name->attr_get_i('href');
			$name    = $name->as_trimmed_text;
			if ($age) {
				$age  = $age->as_trimmed_text;
				$name =~ s/ \($age\)$//;
			}
			# say $death->as_HTML('<>&', "\t");
			my $city      = $death->look_down(class=>"cellule ville liste_virgule alone");
			unless ($city) {
				$city     = $death->look_down(class=>"cellule ville liste_virgule");
			}
			$city         = $city->find('a');
			my ($cityName, $cityUrl);
			if ($city) {
				$cityUrl  = $city->attr_get_i('href');
				$cityName = $city->as_trimmed_text;
			}

			# say "name     : $name";
			# say "age      : $age";
			# say "deathUrl : $deathUrl";
			# say "cityName : $cityName";
			# say "cityUrl  : $cityUrl";
			unless ($data{$deathUrl}) {
				$knownDeaths++;
				$data{$deathUrl}->{'name'}     = $name;
				$data{$deathUrl}->{'cityName'} = $cityName;
				$data{$deathUrl}->{'cityUrl'}  = $cityUrl;
				$data{$deathUrl}->{'age'}      = undef;
			}
			# die;
		}
	} else {
		last;
	}
}
die unless keys %data;
# say "raw_data/libramemoria/libramemoria_" . "$date.json";
open my $out, '>:utf8', $dailyFile or die $!;
print $out encode_json\%data;
close $out;
say "";
say "*" x 50;
say "On          [$date]";
say "Found       : $knownDeaths";