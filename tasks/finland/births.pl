#!/usr/bin/perl
use strict;
use warnings;
use Statistics::Descriptive;

my %data = (
    2010 => 60980, 2011 => 59961, 2012 => 59493, 2013 => 58134, 2014 => 57232,
    2015 => 55472, 2016 => 52814, 2017 => 50321, 2018 => 47577, 2019 => 45613,
    2020 => 46463, 2021 => 49594, 2022 => 44951
);

my @decade = @data{2010..2019};
my @recent_years = @data{2020..2022};

my $stat = Statistics::Descriptive::Full->new();
$stat->add_data(@decade);
my $decade_stddev = $stat->standard_deviation();

foreach my $year (2020..2022) {
    my $z = ($data{$year} - mean(@decade)) / $decade_stddev;
    print "Z-score for $year: $z\n";
}

sub mean {
    my @data = @_;
    my $total = 0;
    $total += $_ for @data;
    return $total / @data;
}

