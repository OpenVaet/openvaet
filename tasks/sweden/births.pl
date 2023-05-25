#!/usr/bin/perl
use strict;
use warnings;
use Statistics::Descriptive;

my %data = (
    2010 => 115641, 2011 => 111770, 2012 => 113177, 2013 => 113593, 2014 => 114907,
    2015 => 114870, 2016 => 117425, 2017 => 115416, 2018 => 115832, 2019 => 114523,
    2020 => 113077, 2021 => 114263, 2022 => 104734
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


