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

make_path('twitter_data')
    unless (-d 'twitter_data');

# API limits        : https://developer.twitter.com/en/portal/products
# Twitter tutorials : https://developer.twitter.com/en/docs/tutorials
# Postman API V2    : https://www.postman.com/twitter/workspace/twitter-s-public-workspace/collection/9956214-784efcda-ed4c-4491-a4c0-a26470a67400?ctx=documentation

# Fetching configuration required (bearer token).
my $configurationFile    = 'tasks/twitter/api_config.cfg';
my %apiConfig            = ();
get_config();
my $bearerToken          = $apiConfig{'bearerToken'}        || die;
my $twitterUsersBansFile = 'twitter_data/twitter_users_bans_finalized.json';

# UA used to scrap target.
my $cookie               = HTTP::Cookies->new();
my $ua                   = LWP::UserAgent->new
(
    timeout              => 30,
    cookie_jar           => $cookie,
    agent                => 'Mozilla/5.0 (Windows NT 6.3; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/77.0.3865.90 Safari/537.36'
);
my @headers = (
    'Authorization'      => 'Bearer ' . $bearerToken,
    'Accept'             => '*/*',
    'Accept-Encoding'    => 'gzip, deflate, br',
    'Connection'         => 'keep-alive'
);

my $maxUserResults       = 1000;      # Defines how many users we will get by query
my $maxTweetsResults     = 100;       # Defines how many tweets we will get by query
my $sleepSecondsOnFail   = 10;        # Defines how long we will sleep on a failed query.
my $sleepSeconds         = 900;       # Defines how long we will sleep on a "Too Many Requests" server reply.
my $delayBetweenUpdates  = 3600 * 1;  # Time we wait (in seconds) between followers updates on a given profile.

verify_banned_users();

sub verify_banned_users {
    my $twitterUsersBansJson = json_from_file($twitterUsersBansFile);
    my @cleanedUsers;
    my $hasChanged  = 0;
    my %bannedUsers = ();
    for my $obj (@$twitterUsersBansJson) {
        my %obj = %$obj;
        my $twitterUserName    = $obj{'twitterUserName'};
        my $twitterId          = $obj{'twitterId'};
        my $banDate            = $obj{'banDate'};
        my $banSpecificReasons = $obj{'banSpecificReasons'};
        my $localUrl           = $obj{'localUrl'};
        my $restorationDate    = $obj{'restorationDate'};
        next if defined $restorationDate;

        # Verify if the user ban has been lifted.
        my $isBanned = verify_user_ban($twitterId, $twitterUserName);
        if ($isBanned == 0) {
            say "Enter restoration date for [$twitterUserName]";
            my $restorationDate;
            while (!$restorationDate) {
                $restorationDate = <STDIN>;
                chomp $restorationDate;
                unless ($restorationDate =~ /....-..-../) {
                    say "Error on restoration date format, enter a valid date.";
                    $restorationDate = undef;
                }
            }

            # Calculating time between ban date & ban lifting.
            my $timeBetweenBans = time::calculate_days_difference($banDate, "$restorationDate 12:00:00");
            if (defined $timeBetweenBans) {
                $obj{'restorationDate'} = $restorationDate;
                $obj{'timeBetweenBans'} = $timeBetweenBans;
                $hasChanged = 1;
            } else {
                die "?";
            }
        } else {
            # Fix which can be removed once twitter_anticensor is adjusted to the fact people are coming back.
            unless (exists $obj{'restorationDate'}) {
                $obj{'restorationDate'} = undef;
                $obj{'timeBetweenBans'} = undef;
                $hasChanged = 1;
            }
        }
        say "isBanned : [$isBanned]";
        push @cleanedUsers, \%obj;
    }
    if ($hasChanged) {
        open my $out, '>:utf8', $twitterUsersBansFile;
        print $out encode_json\@cleanedUsers;
        close $out;
    }
    # p$twitterUsersBansJson;
    # die;
}

sub get_config {
    die "missing file [$configurationFile]" unless -f $configurationFile;
    my $json   = json_from_file($configurationFile);
    %apiConfig = %$json;
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

sub verify_user_ban {
    my ($twitterId, $twitterUserName) = @_;
    my $twitterProfileUrl         = "https://api.twitter.com/2/users/by/username/$twitterUserName?user.fields=" .
                                    "created_at,description,entities,id,location,name,pinned_tweet_id,profile_image_url," .
                                    "protected,public_metrics,url,username,verified,withheld";
    say "Getting  [$twitterUserName] data";
    my $res = $ua->get($twitterProfileUrl, @headers);
    unless ($res->is_success)
    {
        p$res;
        die "failed to get [$twitterProfileUrl]";
    }
    my $content = $res->decoded_content;
    my $contentJson;
    eval {
        $contentJson = decode_json($content);
    };
    if ($@) {
        die "Failed to get a proper response from Twitter. Please verify your API configuration file : [$configurationFile]";
    }
    my $isBanned = 0;
    my %userData = %$contentJson;
    if ($userData{'errors'}) {
        my @errorData = @{$userData{'errors'}};
        my $errorData = shift @errorData;
        my %errorData = %$errorData;
        my $detail    = $errorData{'detail'} // die;
        if ($detail) {
            $isBanned = 1 if $detail =~ /User has been suspended:/;
        }
    }
    return $isBanned;
}