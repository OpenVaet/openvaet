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
use WWW::Telegram::BotAPI;

# Project's libraries.
use FindBin;
use lib "$FindBin::Bin/../../lib";
use time;
use global;

my %config               = ();
my $configurationFile    = 'tasks/social_networks/config.cfg';
my $forwardedTweetsFile  = 'social_networks_data/twitter_tweets_forwarded.json'; 
get_config();
my $telegramToken        = $config{'telegramToken'}              // die;

# Initiates Telegram API.
my $telegramApi = WWW::Telegram::BotAPI->new (
    token => $telegramToken
);
my $telegramBotName = $telegramApi->getMe->{result}{username};
say"Initiated Telegram Bot [$telegramBotName] ...";
die unless (-f $forwardedTweetsFile);
my $hasSent = 0;
send_message();
while ($hasSent == 1) {
    $hasSent = 0;
    send_message();
    sleep 3;
}

sub send_message {
    my $json = json_from_file($forwardedTweetsFile);
    my @forwardedTweets = @$json;
    my @forwardedTweetsOut;
    for my $fileData (@$json) {
        my $url = %$fileData{'url'} // die;
        my $review = %$fileData{'review'} // die;
        my $forward = %$fileData{'forward'} // die;
        my $forwarded = %$fileData{'forwarded'} // 0;
        my %o = %$fileData;
        if ($review == 1 && $forward == 1 && !$forwarded) {
            if ($hasSent == 0) {
                $hasSent = 1;
                say "Sending [$url]";
                $url =~ s/twitter\.com/vxtwitter\.com/;
                $telegramApi->sendMessage ({
                    chat_id => -1001732658731,
                    text    => $url
                });
                say "Sent the message !";
                $o{'forwarded'} = 1;
            }
            # die;
        }
        push @forwardedTweetsOut, \%o;
    }

    open my $out, '>:utf8', $forwardedTweetsFile or die $!;
    print $out encode_json\@forwardedTweetsOut;
    close $out;
}

sub get_config {
    die "missing file [$configurationFile]" unless -f $configurationFile;
    my $json   = json_from_file($configurationFile);
    %config = %$json;
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