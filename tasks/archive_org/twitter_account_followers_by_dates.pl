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

# Project's libraries.
use FindBin;
use lib "$FindBin::Bin/../../lib";
use time;

# UA used to scrap target.
my $cookie               = HTTP::Cookies->new();
my $ua                   = LWP::UserAgent->new
(
    timeout              => 30,
    cookie_jar           => $cookie,
    agent                => 'Mozilla/5.0 (Windows NT 6.3; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/77.0.3865.90 Safari/537.36'
);

# Fetching the targeted Twitter alias.
my ($twitterUserName, $twitterUrl, $twitterUrlFormatted);
get_target_alias();

# Fetching the years with active archives for that alias.
my %years = ();
fetch_years();

# Fetching the dates by years on which we have archives.
my %dates = ();
fetch_yearly_dates();

# Fetching the hours every 7 days at least.
my %followers = ();
fetch_dates_hours();

p%followers;

sub get_target_alias {
    say "Please enter the twitter alias of your target (for example, for user [https://twitter.com/OpenvaetFan], alias is [OpenvaetFan])";
    $twitterUserName     = <STDIN>;
    chomp $twitterUserName;
    $twitterUrl          = "https://twitter.com/$twitterUserName";
    $twitterUrlFormatted = $twitterUrl;
    $twitterUrlFormatted =~ s/:/\%3A/g;
    $twitterUrlFormatted =~ s/\//\%2F/g;
}

sub fetch_years {

    # Setting headers & URL.
    my $path    = "/__wb/sparkline?output=json&url=$twitterUrlFormatted&collection=web";
    my @headers = set_headers($path, $twitterUrl);
    my $url     = "https://web.archive.org$path";
    say "Getting years";

    # Getting data.
    my $res     = $ua->get($url, @headers);
    unless ($res->is_success)
    {
        p$res;
        die "failed to get [$url]";
    }
    my $content = $res->decoded_content;
    my $contentJson;
    eval {
        $contentJson = decode_json($content);
    };
    if ($@) {
        die "Failed to get a proper response from [$url].";
    }

    # Listing years.
    if (%$contentJson{'years'}) {
        for my $year (sort keys %{%$contentJson{'years'}}) {
            $years{$year} = 1;
        }
    }
}

sub set_headers {
    my ($path, $twitterUrl) = @_;
    my @headers = (
        'Accept'          => '*/*',
        'Accept-Encoding' => 'gzip, deflate, br',
        'Connection'      => 'keep-alive',
        ':Authority'      => 'web.archive.org',
        ':Method'         => 'GET',
        ':Path'           => $path,
        ':Scheme'         => 'https',
        'Referer'         => "https://web.archive.org/web/20220000000000*/$twitterUrl",
        'sec-fetch-mode'  => 'cors',
        'sec-fetch-site'  => 'same-origin'
    );
    return @headers;
}

sub fetch_yearly_dates {
    for my $year (sort{$a <=> $b} keys %years) {
        say "Getting dates - [$year]";
        my $path    = "/__wb/calendarcaptures/2?url=$twitterUrlFormatted&date=$year&groupby=day";
        my @headers = set_headers($path, $twitterUrl);
        my $url     = "https://web.archive.org$path";

        # Getting data.
        my $res     = $ua->get($url, @headers);
        unless ($res->is_success)
        {
            p$res;
            die "failed to get [$url]";
        }
        my $content = $res->decoded_content;
        my $contentJson;
        eval {
            $contentJson = decode_json($content);
        };
        if ($@) {
            die "Failed to get a proper response from [$url].";
        }
        if (%$contentJson{'items'}) {
            for my $item (@{%$contentJson{'items'}}) {
                my $monthDay = @$item[0] // die;
                my $hits     = @$item[2] // die;
                my ($month,
                    $day) = $monthDay =~ /(.*)(..)$/;
                die unless $month && $day;
                $month = "0$month" if ($month < 10);
                $dates{$year}->{$month}->{$day} = $hits;
            }
        }
    }
}

sub fetch_dates_hours {
    make_path("archive_org_data/$twitterUserName/json")
        unless (-d "archive_org_data/$twitterUserName/json");
    make_path("archive_org_data/$twitterUserName/hours")
        unless (-d "archive_org_data/$twitterUserName/hours");
    make_path("archive_org_data/$twitterUserName/html")
        unless (-d "archive_org_data/$twitterUserName/html");
    my ($current, $total) = (0, 0);
    for my $year (sort{$a <=> $b} keys %dates) {
        for my $month (sort{$a <=> $b} keys %{$dates{$year}}) {
            for my $day (sort{$a <=> $b} keys %{$dates{$year}->{$month}}) {
                $total++;
            }
        }
    }
    for my $year (sort{$a <=> $b} keys %dates) {
        for my $month (sort{$a <=> $b} keys %{$dates{$year}}) {
            for my $day (sort{$a <=> $b} keys %{$dates{$year}->{$month}}) {
                $current++;
                STDOUT->printflush("\rGetting archives - [$current / $total]");

                # Getting last hour of the day.
                my $hour = get_hour($year, $month, $day);
                my ($h, $m, $s) = $hour =~ /(.*)(..)(..)$/;
                if (!$h) {
                    ($h, $m, $s) = $hour =~ /(.)(.)(..)$/;
                    unless (defined $h) {
                        ($m, $s) = $hour =~ /(.*)(..)$/;
                        die unless defined $m;
                        $h = 0;
                    }
                    die "$year-$month-$day - hour : $hour" unless defined $h;
                }
                $h = "0$h" if $h < 10;

                # Getting archived page if we haven't stored it already.
                my $dateHour = "$year$month$day$h$m$s";
                my $hFile    = "archive_org_data/$twitterUserName/json/$dateHour.json";
                my $followersCount;
                unless (-f $hFile) {
                    my $content;
                    my $file = "archive_org_data/$twitterUserName/html/$dateHour.html";
                    unless (-f $file) {
                        my $path    = "/web/$dateHour/$twitterUrl";
                        my @headers = set_headers($path, $twitterUrl);
                        my $url     = "https://web.archive.org$path";
                        my $res     = $ua->get($url, @headers);
                        unless ($res->is_success)
                        {
                            next
                        }
                        $content    = $res->decoded_content;
                        open my $out, '>:utf8', $file;
                        print $out $content;
                        close $out;
                    } else {
                        open my $in, '<:utf8', $file;
                        while (<$in>) {
                            $content .= $_;
                        }
                        close $in;
                    }
                    my $tree    = HTML::Tree->new();
                    $tree->parse($content);
                    if ($tree->look_down(id=>"init-data")) {
                        my $input          = $tree->look_down(id=>"init-data");
                        my $json           = $input->attr_get_i('value');
                        open my $out, '>:utf8', $hFile;
                        print $out $json;
                        close $out;
                    } else {

                        $followersCount = attempt_html($tree);
                        next unless $followersCount;
                    }
                }
                if (-f $hFile) {
                    my $json           = json_from_file($hFile);
                    unless (%$json{'profile_user'}) {
                        next;
                    } else {
                        my %userData = %{%$json{'profile_user'}};
                        $followersCount = $userData{'followers_count'} // die;
                    }
                }
                $followers{$dateHour}->{'followersCount'} = $followersCount;
            }
        }
    }
}

sub get_hour {
    my ($year, $month, $day) = @_;
    my $file     = "archive_org_data/$twitterUserName/hours/$year$month$day.json";
    my $content;
    unless (-f $file) {
        my $path    = "/__wb/calendarcaptures/2?url=$twitterUrlFormatted&date=$year$month$day";
        my @headers = set_headers($path, $twitterUrl);
        my $url     = "https://web.archive.org$path";
        my $res     = $ua->get($url, @headers);
        unless ($res->is_success)
        {
            return;
        }
        $content    = $res->decoded_content;
        open my $out, '>:utf8', $file;
        print $out $content;
        close $out;
    } else {
        open my $in, '<:utf8', $file;
        while (<$in>) {
            $content .= $_;
        }
        close $in;
    }
    my $contentJson;
    eval {
        $contentJson = decode_json($content);
    };
    if ($@) {
        die "Failed to parse json on [$file].";
    }
    die unless %$contentJson{'items'};
    my $lastHour;
    for my $item (@{%$contentJson{'items'}}) {
        my $hour  = @$item[0] // die;
        $lastHour = $hour;
    }
    die unless $lastHour;
}

sub json_from_file {
    my $file = shift;
    if (-f $file) {
        my $json;
        eval {
            open my $in, '<:utf8', $file;
            while (<$in>) {
                $json .= $_;
            }
            close $in;
            $json = decode_json($json) or die $!;
        };
        if ($@) {
            {
                local $/;
                open (my $fh, $file) or die $!;
                $json = <$fh>;
                close $fh;
            }
            eval {
                $json = decode_json($json);
            };
            if ($@) {
                die "failed parsing json : " . @!;
            }
        }
        return $json;
    } else {
        return {};
    }
}

sub attempt_html {
    my $tree = shift;
    my @urls = $tree->find('a');
    for my $urlData (@urls) {
        next unless $urlData->attr_get_i('href');
        my $href = $urlData->attr_get_i('href') // die;
        next unless $href =~ /\/followers$/;
        my $followersCount = $urlData->as_trimmed_text;
        die unless $followersCount =~ /Followers$/;
        $followersCount =~ s/ Followers$//;
        my $replace;
        if ($followersCount =~ /\./) {
            my (undef, $ext) = split '\.', $followersCount;
            if ($ext =~ /K/) {
                my $lExt = 3 - (length $ext) + 1;
                $replace = '0' x $lExt;
            } else {
                my $lExt = 3 - length $ext;
                $replace = '0' x $lExt;
            }
        } else {
            $replace = '000';
        }
        $followersCount =~ s/K/$replace/;
        $followersCount =~ s/\.//;
        return $followersCount;
    }
}