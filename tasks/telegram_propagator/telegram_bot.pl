#!/usr/bin/perl
use strict;
use warnings;
use 5.26.0;
no autovivification;
binmode STDOUT, ":utf8";
use utf8;
use POSIX;
use URI::Escape;
use HTTP::Request;
use HTTP::Request::Common;
use HTTP::Cookies;
use HTML::Tree;
use LWP::UserAgent;
use LWP::Simple;
use Data::Printer;
use Data::Dumper;
use File::Path qw(make_path);
use WWW::Telegram::BotAPI;
use JSON;
use File::stat;
use MIME::Base64;

=head
    ----------------------------------------
    CONFIGURATION FOR TELEGRAM API
    ________________________________________
    1. Get to https://t.me/BotFather
    2. Type /newbot and register a name & username for the bot in order to get a Telegram Token.
    3. Put your Telegram Token in the .cfg file.
    4. Invite your Bot to your channel as Administrator.


    ----------------------------------------
    CONFIGURATION FOR Gab POSTING
    ________________________________________
    1. Put your credentials in the tasks/telegram_propagator/config.cfg file.


    ----------------------------------------
    CONFIGURATION FOR Gettr POSTING
    ________________________________________
    1. Put your credentials in the tasks/telegram_propagator/config.cfg file.
=cut

# Fetches config data from file.
my $configurationFile          = 'tasks/telegram_propagator/config.cfg';
my %config                     = ();
my @gabGroups;
get_config();
my $sleepSecondsBetweenUpdates = $config{'sleepSecondsBetweenUpdates'} // die; # Time we wait until to pull the new messages on Telegram.
my $replicateTgToGettrFeed     = $config{'replicateTgToGettrFeed'}     // die; # Either 0 or 1. Will publish on Gettr's user feed if set to 1.
my $replicateTgToGabFeed       = $config{'replicateTgToGabFeed'}       // die; # Either 0 or 1. Will publish on Gab's user feed if set to 1.
my $replicateTgToGabGroups     = $config{'replicateTgToGabGroups'}     // die; # Either 0 or 1. Will publish on every Gab Groups configured in the .cfg file if set to 1.
my $telegramToken              = $config{'telegramToken'}              // die;
my $gabAlias                   = $config{'gabAlias'}                   // die;
my $gabUserName                = $config{'gabUserName'}                // die;
my $gabUserPassword            = $config{'gabUserPassword'}            // die;
my $gettrUserName              = $config{'gettrUserName'}              // die;
my $gettrUserPassword          = $config{'gettrUserPassword'}          // die;
my $gabGroupsPostingVisibility = 'public'; # Either "public" or "unlisted". To adjust if the behavior varies on your Gab account.

# Initiates UserAgent.
my $cookie = HTTP::Cookies->new();
my $ua     = LWP::UserAgent->new
(
    timeout    => 30,
    cookie_jar => $cookie,
    agent      => 'Mozilla/5.0 (Windows NT 6.3; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/77.0.3865.90 Safari/537.36'
);

my ($gettrId, $gettrToken, $gettrRToken, $gettrCDate, $gettrUDate);
if ($replicateTgToGettrFeed) {
    init_gettr_session();
}

# Initiates Gab session.
my ($gabAuthToken, $gabUriAuthToken, $gabToken);
if ($replicateTgToGabFeed || $replicateTgToGabGroups) {
    init_gab_session();
}

# Initiates Telegram API.
my $telegramApi = WWW::Telegram::BotAPI->new (
    token => $telegramToken
);

# Initiates Telegram watching loop.
my %messages = ();
while (1) {
    %messages = ();

    # Gets the Telegram updates.
    get_telegram_updates();

    # Prints the posts content (mainly for debug purposes in this early version).
    print_telegram_updates();
    sleep $sleepSecondsBetweenUpdates;
}

sub get_config {
    die "missing file [$configurationFile]" unless -f $configurationFile;
    my $json = json_from_file($configurationFile);
    %config  = %$json;
    die "Missing setting [replicateTgToGabFeed]"   unless exists $config{'replicateTgToGabFeed'}   && ($config{'replicateTgToGabFeed'}   == 0 || $config{'replicateTgToGabFeed'}   == 1);
    die "Missing setting [replicateTgToGabGroups]" unless exists $config{'replicateTgToGabGroups'} && ($config{'replicateTgToGabGroups'} == 0 || $config{'replicateTgToGabGroups'} == 1);
    if ($config{'replicateTgToGabGroups'} == 1) {
        die "Missing array [gabGroups]" unless exists $config{'gabGroups'};
        for my $gabGroupId (@{$config{'gabGroups'}}) {
            push @gabGroups, $gabGroupId;
        }
    }
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

sub current_datetime
{
    my $currentDatetime = strftime "%Y-%m-%d %H:%M:%S", localtime time;
    return $currentDatetime;
}

sub print_log {
    my $message = shift;
    my $currentDatetime = current_datetime();
    open my $out, '>>:utf8', 'tasks/telegram_propagator/telegram_bot_logs.txt';
    say "$currentDatetime - $message";
    say $out "$currentDatetime - $message";
    close $out;
}

sub init_gab_session {

    # First of all, we need a token which is randomly generated by Gab when a user initiates a session
    $gabAuthToken    = get_gab_home();

    # Second, we need to convert the token to URI compatible format. We may need to also convert passwords with special characters the same way.
    $gabUriAuthToken = uri_escape($gabAuthToken);

    # We then login to Gab, and retrieve the User token which will allow us to Post.
    login_gab();
    $gabToken        = get_gab_token();
}

sub get_gab_home {
    print_log("Getting Gab Authenticity Token ...");
    my $url     = "https://gab.com/";
    my $res     = $ua->get($url);
    my $content = $res->decoded_content;
    my $tree    = HTML::Tree->new();
    $tree->parse($content);
    my $meta    = $tree->look_down(name=>"csrf-token");
    my $authenticityToken = $meta->attr_get_i('content');
    return $authenticityToken;
}

sub login_gab {
    print_log("Initiating Gab session ...");
    my @headers = (
        ':Authority'                => 'gab.com',
        ':Method'                   => 'POST',
        ':Path'                     => '/auth/sign_in',
        ':Scheme'                   => 'https',
        'Accept'                    => 'text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,*/*;q=0.8',
        'Accept-Encoding'           => 'gzip, deflate',
        'Accept-Language'           => 'en-US,en;q=0.9',
        'Cache-Control'             => 'max-age=0',
        'Connection'                => 'keep-alive',
        'Content-Type'              => 'application/x-www-form-urlencoded',
        'Origin'                    => 'https://gab.com',
        'Referer'                   => "https://gab.com/auth/sign_in",
        'sec-ch-ua'                 => 'Google Chrome";v="105", "Not)A;Brand";v="8", "Chromium";v="105"',
        'Sec-Fetch-Dest'            => 'document',
        'Sec-Fetch-Mode'            => 'navigate',
        'Sec-Fetch-Site'            => 'same-origin',
        'Sec-Fetch-User'            => '?1',
        'Sec-GPC'                   => 1,
        'TE'                        => 'trailers',
        'Upgrade-Insecure-Requests' => 1,
        'User-Agent'                => 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/105.0.0.0 Safari/537.36'
    );
    my $url     = "https://gab.com/auth/sign_in";
    my $request = new HTTP::Request( 'POST', $url);
    my $params  = "authenticity_token=$gabUriAuthToken&user[email]=$gabUserName&user[password]=$gabUserPassword&button=";
    $request->header(@headers);
    $request->content($params);
    my $res     = $ua->request($request);
    my $content = $res->decoded_content;
    my $tree    = HTML::Tree->new();
    $tree->parse($content);
    my $text    = $tree->find('body')->as_trimmed_text;
    if ($text eq 'You are being redirected.') {
        print_log("Login to Gab successfull ...");
        return 1;
    } else {
        print_log("Login to Gab failed, verify your configuration file and contact openvaet.org if required.");
        die;
    }
}

sub get_gab_token {
    print_log("Getting Gab User Token ...");
    my $url      = "https://gab.com/$gabAlias";
    my $res      = $ua->get($url);
    my $content  = $res->decoded_content;
    my $tree     = HTML::Tree->new();
    $tree->parse($content);
    my $initSet  = $tree->look_down(id=>"initial-state");
    my $asHTML   = $tree->as_HTML('<>&', "\t");
    my ($json)   = $asHTML =~ /<script id="initial-state" type="application\/json">(.*)<\/script>/;
    # Priting an intermediary JSON file to bypass barbaric encodings.
    my $tmpFile  = 'profile_' .  generate_random_number(5) . '.json';
    open my $out, '>:utf8', $tmpFile;
    print $out $json;
    close $out;
    $json        = json_from_file($tmpFile);
    unlink $tmpFile or die "failed to remove temporary file";
    my $gabToken = %$json{'meta'}->{'access_token'} // die;
    return $gabToken;
}

sub post_on_gab {
    my ($channelName, $messageId, $groupId) = @_;
    if ($groupId) {
        print_log("Re-posting on Gab's Group [$groupId] Telegram message [$channelName -> $messageId] ...");
    } else {
        print_log("Re-posting on Gab Telegram message [$channelName -> $messageId] ...");
    }
    my $file = "telegram_data/$channelName/$messageId/message.json";
    open my $in, '<:utf8', $file;
    my $json;
    while (<$in>) {
        $json .= $_;
    }
    close $in;
    $json = decode_json($json);
    print_log("Retrieved Telegram message ...");

    # If we have a document attachment, we verify its a video or picture, and proceed with uploading.
    my @mediaIds;
    my $hasIncompatibleMedia = 0;
    if (%$json{'documents'}) {
        for my $file (@{%$json{'documents'}}) {
            my @elems = split '\.', $file;
            my $ext   = $elems[scalar @elems - 1] // die;
            if ($ext eq 'mp4'             || $ext eq 'jpg'        || $ext eq 'jpeg'      || $ext eq 'png' || $ext eq 'gif' ||
                $ext eq 'webp'            || $ext eq 'jfif'       || $ext eq 'webm'      || $ext eq 'm4v' || $ext eq 'mov' ||
                $ext eq 'image/jpeg'      || $ext eq 'image/png'  || $ext eq 'image/gif' ||
                $ext eq 'image/webp'      || $ext eq 'image/webm' || $ext eq 'image/mp4' ||
                $ext eq 'image/quicktime' || $ext eq 'image/ogg'  || $ext eq 'image/3gpp'
            ) {
                my $mediaId = upload_gab_media($file);
                push @mediaIds, $mediaId;
            } else {
                $hasIncompatibleMedia = 1;
            }
        }
    }
    my $text   = %$json{'text'};
    if ($hasIncompatibleMedia == 1) {
        # Prettifying the format here.
        $text .= "\n\nThis message was automatically copied from this Telegram post : https://t.me/$channelName/$messageId";
    }
    my @headers = (
        ':Authority'                => 'gab.com',
        ':Method'                   => 'POST',
        ':Path'                     => '/auth/sign_in',
        ':Scheme'                   => 'https',
        'Accept'                    => 'application/json, text/plain, */*',
        'Accept-Encoding'           => 'gzip, deflate',
        'Accept-Language'           => 'en-US,en;q=0.9',
        'Authorization'             => "Bearer $gabToken",
        'Cache-Control'             => 'max-age=0',
        'Connection'                => 'keep-alive',
        'Content-Type'              => 'application/json;charset=utf-8',
        'Origin'                    => 'https://gab.com',
        'Referer'                   => "https://gab.com",
        'sec-ch-ua'                 => 'Google Chrome";v="105", "Not)A;Brand";v="8", "Chromium";v="105"',
        'Sec-Fetch-Dest'            => 'empty',
        'Sec-Fetch-Mode'            => 'cors',
        'Sec-Fetch-Site'            => 'same-origin',
        'Sec-Fetch-User'            => '?1',
        'Sec-GPC'                   => 1,
        'TE'                        => 'trailers',
        'Upgrade-Insecure-Requests' => 1,
        'User-Agent'                => 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/105.0.0.0 Safari/537.36',
        'X-CSRF-Token'              => $gabAuthToken
    );
    my $url     = "https://gab.com/api/v1/statuses";
    my $request = new HTTP::Request( 'POST', $url);
    my %params  = ();
    $params{'expires_at'}     = undef;
    if ($groupId) {
        $params{'group_id'}   = $groupId;
        $params{'visibility'} = 'public';
    } else {
        $params{'group_id'}   = undef;
        $params{'visibility'} = 'public';
    }
    $params{'in_reply_to_id'} = undef;
    $params{'markdown'}       = $text;
    $params{'media_ids'}      = \@mediaIds;
    $params{'poll'}           = undef;
    $params{'quote_of_id'}    = undef;
    $params{'scheduled_at'}   = undef;
    $params{'sensitive'}      = 'false';
    $params{'spoiler_text'}   = '';
    $params{'status'}         = $text;
    my $params = encode_json\%params;
    $request->header(@headers);
    $request->content($params);
    my $res     = $ua->request($request);
    my $content = $res->decoded_content;
    print_log("Successfully Posted Message to Gab ...");
}

sub upload_gab_media {
    my ($file) = @_;
    print_log("Uploading file [$file] to Gab ...");
    my $randString30 = generate_random_number(30);
    my @headers = (
        'Accept'                    => 'application/json, text/plain, */*',
        'Accept-Encoding'           => 'gzip, deflate',
        'Accept-Language'           => 'en-US,en;q=0.9',
        'Authorization'             => "Bearer $gabToken",
        'Connection'                => 'keep-alive',
        'Content-Type'              => "multipart/form-data; boundary=-----------------------------$randString30",
        'Host'                      => 'gab.com',
        'Origin'                    => 'https://gab.com',
        'Referer'                   => "https://gab.com/",
        'Sec-Fetch-Dest'            => 'empty',
        'Sec-Fetch-Mode'            => 'cors',
        'Sec-Fetch-Site'            => 'same-origin',
        'Sec-GPC'                   => 1,
        'User-Agent'                => 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/105.0.0.0 Safari/537.36',
        'X-CSRF-Token'              => $gabAuthToken
    );
    my $url     = "https://gab.com/api/v1/media";
    my @elems   = split '\/', $file;
    my $name    = $elems[scalar @elems - 1] // die;
    my $request = HTTP::Request::Common::POST(
      $url, @headers,
      Content       => [ file => [$file] ],
    );
    my $res     = $ua->request($request);
    my $content = $res->decoded_content;
    my $json    = decode_json($content);
    my $type    = %$json{'type'};
    unless ($type) {
        print_log("Failed uploading file [$file] to Gab ...");
        die;
    }
    print_log("Success uploading [$file] to Gab ...");
    return %$json{'id'};
}

sub get_telegram_updates {
    print_log("Getting Telegram Channels Last Updates ...");
    my $offset      = "-$sleepSecondsBetweenUpdates";
    my $updates     = $telegramApi->getUpdates ({
        timeout => 0,
        $offset ? (offset => $offset) : ()
    });
    my %attachments = ();
    if (%$updates{'result'}) {
        for my $result (@{%$updates{'result'}}) {
            if (%$result{'channel_post'} || %$result{'edited_channel_post'}) {
                my $channelLabel;
                if (%$result{'channel_post'}) {
                    $channelLabel = 'channel_post';
                } elsif (%$result{'edited_channel_post'}) {
                    $channelLabel = 'edited_channel_post';
                } else {
                    die "Option to code";
                }
                my $channelId    = %$result{$channelLabel}->{'chat'}->{'id'}       // die;
                $channelId       =~ s/\-//;
                my $channelName  = %$result{$channelLabel}->{'chat'}->{'username'} // %$result{$channelLabel}->{'chat'}->{'title'} // die;
                my $uts          = %$result{$channelLabel}->{'date'} // die;
                my $messageId    = %$result{$channelLabel}->{'message_id'} // die;
                my $text         = %$result{$channelLabel}->{'text'} // %$result{$channelLabel}->{'caption'};
                my $mediaGroupId = %$result{$channelLabel}->{'media_group_id'};
                if ($mediaGroupId) {
                    $messageId   = $mediaGroupId;
                }
                $messages{$channelName}->{$messageId}->{'uts'}       = $uts;
                $messages{$channelName}->{$messageId}->{'text'}      = $text if $text;
                if (%$result{$channelLabel}->{'document'}) {
                    my $fileId      = %$result{$channelLabel}->{'document'}->{'file_id'}   // die;
                    my $fileName    = %$result{$channelLabel}->{'document'}->{'file_name'} // die;
                    my $fileDetails = $telegramApi->getFile({file_id => $fileId});
                    my $filePath    = %$fileDetails{'result'}->{'file_path'} // die;   
                    my $fileUrl     = "https://api.telegram.org/file/bot$telegramToken/$filePath";
                    my $localFolder = "telegram_data/$channelName/$messageId/documents";
                    make_path($localFolder) unless (-d $localFolder);
                    my $localFile   = "$localFolder/$fileName";
                    unless (-f $localFile) {
                        my $rc = getstore($fileUrl, $localFile);
                        if (is_error($rc)) {
                            die "getstore of <$fileUrl> failed with $rc";
                        }
                    }
                    push @{$messages{$channelName}->{$messageId}->{'documents'}}, $localFile;
                }
                if (%$result{$channelLabel}->{'photo'}) {
                    my $localFolder = "telegram_data/$channelName/$messageId/documents";
                    make_path($localFolder) unless (-d $localFolder);
                    $attachments{$channelName}->{$messageId}->{'fNum'}++;
                    my $fNum = $attachments{$channelName}->{$messageId}->{'fNum'} // die;
                    my $fileId;
                    for my $photo (@{%$result{$channelLabel}->{'photo'}}) {
                        $fileId   = %$photo{'file_id'}   // die;
                    }
                    my $fileDetails = $telegramApi->getFile({file_id => $fileId});
                    my $filePath    = %$fileDetails{'result'}->{'file_path'} // die;   
                    my $fileUrl     = "https://api.telegram.org/file/bot$telegramToken/$filePath";
                    my @elems       = split '\.', $fileUrl;
                    my $ext         = $elems[(scalar @elems - 1)] // die;
                    my $localFile   = "$localFolder/$fNum.$ext";
                    push @{$messages{$channelName}->{$messageId}->{'documents'}}, $localFile;
                    unless (-f $localFile) {
                        my $rc = getstore($fileUrl, $localFile);
                        if (is_error($rc)) {
                            die "getstore of <$fileUrl> failed with $rc";
                        }
                    }
                }
                if (%$result{$channelLabel}->{'video'}) {
                    my $fileId      = %$result{$channelLabel}->{'video'}->{'file_id'}   // die;
                    my $fileName    = %$result{$channelLabel}->{'video'}->{'file_name'} // die;
                    my $fileDetails = $telegramApi->getFile({file_id => $fileId});
                    my $filePath    = %$fileDetails{'result'}->{'file_path'} // die;   
                    my $fileUrl     = "https://api.telegram.org/file/bot$telegramToken/$filePath";
                    my $localFolder = "telegram_data/$channelName/$messageId/documents";
                    make_path($localFolder) unless (-d $localFolder);
                    my $localFile   = "$localFolder/$fileName";
                    unless (-f $localFile) {
                        my $rc = getstore($fileUrl, $localFile);
                        if (is_error($rc)) {
                            die "getstore of <$fileUrl> failed with $rc";
                        }
                    }
                    push @{$messages{$channelName}->{$messageId}->{'documents'}}, $localFile;
                }
            } else {
                say "Unknown result type";
                p$result;
            }
        }
    }
}

sub init_gettr_session {
    ($gettrId, $gettrToken, $gettrRToken, $gettrCDate, $gettrUDate) = login_gettr();
}

sub login_gettr {
    my @headers = (
        ':Authority'                => 'api.gettr.com',
        ':Method'                   => 'POST',
        ':Path'                     => '/u/post',
        ':Scheme'                   => 'https',
        'Accept'                    => 'application/json, text/plain, */*',
        'Accept-Encoding'           => 'gzip, deflate',
        'Accept-Language'           => 'en-US,en;q=0.9',
        'Cache-Control'             => 'max-age=0',
        'Connection'                => 'keep-alive',
        'Content-Type'              => 'application/json',
        'Origin'                    => 'https://gettr.com',
        'Referer'                   => "https://gettr.com/",
        'sec-ch-ua'                 => 'Google Chrome";v="105", "Not)A;Brand";v="8", "Chromium";v="105"',
        'Sec-Fetch-Dest'            => 'document',
        'Sec-Fetch-Mode'            => 'navigate',
        'Sec-Fetch-Site'            => 'same-site',
        'Sec-Fetch-User'            => '?1',
        'Sec-GPC'                   => 1,
        'x-app-auth'                => '{"user": null, "token": null}',
        'Upgrade-Insecure-Requests' => 1,
        'User-Agent'                => 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/105.0.0.0 Safari/537.36'
    );
    my $url     = "https://api.gettr.com/u/user/v2/login";
    my $request = new HTTP::Request( 'POST', $url);
    my %params  = ();
    $params{'content'}->{'email'} = $gettrUserName;
    $params{'content'}->{'pwd'}   = $gettrUserPassword;
    $params{'content'}->{'sms'}   = '';
    my $params  = encode_json\%params;
    $request->header(@headers);
    $request->content($params);
    my $res     = $ua->request($request);
    my $content = $res->decoded_content;
    my $contentJson = decode_json($content);
    if (%$contentJson{'rc'} eq 'OK') {
        print_log("Login to Gettr successfull ...");
        return (%$contentJson{'result'}->{'user'}->{'_id'}, %$contentJson{'result'}->{'token'}, %$contentJson{'result'}->{'rtoken'}, %$contentJson{'result'}->{'user'}->{'cdate'}, %$contentJson{'result'}->{'user'}->{'udate'});
    } else {
        p$contentJson;
        print_log("Login to Gettr failed, verify your configuration file and contact openvaet.org if required.");
        die;
    }
}

sub post_on_gettr {
    my ($channelName, $messageId) = @_;
    print_log("Re-posting on Gettr Telegram message [$channelName -> $messageId] ...");
    my $file = "telegram_data/$channelName/$messageId/message.json";
    open my $in, '<:utf8', $file;
    my $json;
    while (<$in>) {
        $json .= $_;
    }
    close $in;
    $json = decode_json($json);
    print_log("Retrieved Telegram message ...");

    # If we have a document attachment, we verify its a video or picture, and proceed with uploading.
    my %fileDetails;
    my @filesDetails = ();
    my $attachmentType;
    my $hasIncompatibleMedia = 0;
    if (%$json{'documents'}) {
        for my $file (@{%$json{'documents'}}) {
            my @elems = split '\.', $file;
            my $ext   = $elems[scalar @elems - 1] // die;
            if ($ext eq 'mp4'  || $ext eq 'gif'  ||
                $ext eq 'webp' || $ext eq 'webm' || $ext eq 'm4v' || $ext eq 'mov'
            ) {
                $attachmentType = 'Video';
                %fileDetails = upload_gettr_media($file, $ext);
            } elsif (
                $ext eq 'jpg'        || $ext eq 'jpeg'      || $ext eq 'png' ||
                $ext eq 'jfif'
            ) {
                $attachmentType = 'Picture';
                my %fileDetails = upload_gettr_media($file, $ext);
                push @filesDetails, \%fileDetails;
            } else {
                $hasIncompatibleMedia = 1;
            }
        }
    }
    my $text   = %$json{'text'};
    if ($hasIncompatibleMedia == 1) {
        # Prettifying the format here.
        $text .= "\n\nThis message was automatically copied from this Telegram post : https://t.me/$channelName/$messageId";
    }
    if (length $text > 750) {
        $text = substr($text, 0, 600);
        $text .= "\n\nThis message was automatically copied from this Telegram post : https://t.me/$channelName/$messageId";
    }
    my %xAppAuth = ();
    $xAppAuth{'user'}  = $gettrId;
    $xAppAuth{'token'} = $gettrToken;
    my $xAppAuth = encode_json\%xAppAuth;
    my $randString30 = generate_random_number(30);
    my @headers  = (
        ':Authority'                => 'gettr.com',
        ':Method'                   => 'POST',
        ':Path'                     => '/auth/sign_in',
        ':Scheme'                   => 'https',
        'Accept'                    => 'application/json, text/plain, */*',
        'Accept-Encoding'           => 'gzip, deflate',
        'Accept-Language'           => 'en-US,en;q=0.9',
        'Content-Type'              => "multipart/form-data; boundary=---------------------------$randString30",
        'enctype'                   => 'multipart/form-data',
        'Host'                      => 'api.gettr.com',
        'Origin'                    => 'https://gettr.com',
        'Referer'                   => "https://gettr.com",
        'sec-ch-ua'                 => 'Google Chrome";v="105", "Not)A;Brand";v="8", "Chromium";v="105"',
        'Sec-Fetch-Dest'            => 'empty',
        'Sec-Fetch-Mode'            => 'cors',
        'Sec-Fetch-Site'            => 'same-site',
        'Sec-Fetch-User'            => '?1',
        'Sec-GPC'                   => 1,
        'TE'                        => 'trailers',
        'ver'                       => '2.7.0',
        'Upgrade-Insecure-Requests' => 1,
        'User-Agent'                => 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/105.0.0.0 Safari/537.36',
        'x-app-auth'                => $xAppAuth
    );
    my $url     = "https://api.gettr.com/u/post";
    my %params  = ();
    if ($attachmentType) {
        if ($attachmentType eq 'Video') {
            p%fileDetails;
            my $screen = $fileDetails{'screen'} // die;
            my $ori = $fileDetails{'ori'} // die;
            my $m3u8 = $fileDetails{'m3u8'} // die;
            my $duration = $fileDetails{'duration'} // die;
            my $vHght = $fileDetails{'height'} // die;
            my $vWid  = $fileDetails{'width'} // die;
            $params{'data'}->{'main'}    = $screen;
            $params{'data'}->{'nmvid'}   = $ori;
            $params{'data'}->{'ovid'}    = $ori;
            $params{'data'}->{'pvid'}    = $m3u8;
            $params{'data'}->{'vid'}     = $m3u8;
            $params{'data'}->{'vid_dur'} = $duration;
            $params{'data'}->{'vid_hgt'} = $vHght;
            $params{'data'}->{'vid_wid'} = $vWid;
        } elsif ($attachmentType eq 'Picture') {
            for my $fileData (@filesDetails) {
                my $ori = %$fileData{'ori'} // die;
                push @{$params{'data'}->{'imgs'}}, $ori;
                push @{$params{'data'}->{'meta'}}, {};
            }
            $params{'data'}->{'vid_hgt'} = 1024;
            $params{'data'}->{'vid_wid'} = 1024;
        } else {
            die "Attachment Type : $attachmentType"
        }
    }
    $params{'aux'}                   = undef;
    $params{'serial'}                = 'post';
    $params{'data'}->{'_t'}          = 'post';
    $params{'data'}->{'acl'}->{'_t'} = 'acl';
    $params{'data'}->{'cdate'}       = $gettrCDate;
    $params{'data'}->{'txt'}         = $text;
    $params{'data'}->{'udate'}       = $gettrUDate;
    $params{'data'}->{'uid'}         = $gettrId;
    # p%params;
    my $params = encode_json\%params;
    # p$params;
    my $request = HTTP::Request::Common::POST(
      $url, @headers,
      Content   => { content => $params }
    );
    my $res     = $ua->request($request);
    my $content = $res->decoded_content;
    my $cJson   = decode_json($content);
    # p$cJson;
    die "Failed to post on Gettr" unless %$cJson{'rc'} eq 'OK';
    print_log("Successfully Posted Message to Getr ...");
}

sub generate_random_number {
    my $length = shift;
    my @int = ('0' ..'9');
    return join '' => map $int[rand @int], 1 .. $length;
}

sub upload_gettr_media {
    my ($file, $ext) = @_;
    print_log("Uploading file [$file] to Gettr ...");
    my ($fileName,
        $fileSize,
        $fileType)   = file_infos($file, $ext);
    my $fileLocation = upload_gettr_file($file, $fileName, $fileSize, $fileType);
    # say "fileLocation : $fileLocation";
    my @headers    = (
        'Accept'                    => '*/*',
        'Accept-Encoding'           => 'gzip, deflate',
        ':Method'                   => 'PATCH',
        'Accept-Language'           => 'en-US,en;q=0.9',
        'Authorization'             => "$gettrToken",
        'Connection'                => 'keep-alive',
        'Content-Type'              => 'application/offset+octet-stream',
        'env'                       => 'prod',
        'filename'                  => $fileName,
        'Host'                      => 'upload.gettr.com',
        'Iv'                        => 0,
        'Origin'                    => 'https://gettr.com',
        'Referer'                   => "https://gettr.com/",
        'Sec-Fetch-Ua'              => '"Google Chrome";v="105", "Not)A;Brand";v="8", "Chromium";v="105"',
        'Sec-Fetch-Dest'            => 'empty',
        'Sec-Fetch-Mode'            => 'cors',
        'Sec-Fetch-Site'            => 'same-site',
        'Tus-Resumable'             => '1.0.0',
        'userid'                    => $gettrId,
        'Upload-Offset'             => 0,
        'User-Agent'                => 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/105.0.0.0 Safari/537.36'
    );
    my $url     = "https://upload.gettr.com$fileLocation";
    my $raw;
    open my $in, '<:raw', $file;
    local $/;
    $raw = <$in>;
    close $in;
    my $request = HTTP::Request::Common::PATCH(
      $url, @headers
    );
    $request->content($raw);
    my $res     = $ua->request($request);
    # p$res;
    my $content = $res->decoded_content;
    # my $headers = $res->headers()->as_string;
    die unless $content;
    my $cJson;
    eval {
        $cJson  = decode_json($content);
    };
    if ($@) {
        say "content :";
        p$content;
        die "Failed parsing server response on file upload [$file]";
    }
    return %$cJson;
}

sub file_infos {
    my ($file, $ext) = @_;
    my @elems     = split '\/', $file;
    my $fileName  = $elems[scalar @elems - 1] // die;
    my $fileStats = stat($file);
    my $fileSize  = $fileStats->size;
    my $fileType  = file_type_from_ext($ext);
    return ($fileName, $fileSize, $fileType);
}

sub upload_gettr_file {
    my ($file, $fileName, $fileSize, $fileType) = @_;
    my $b64Name        = encode_base64( $fileName, '' );
    my $b64FileType    = encode_base64( $fileType, '' );
    my $uploadMetadata = "filename $b64Name,filetype $b64FileType";
    my @headers = (
        'Accept'                    => '*/*',
        'Accept-Encoding'           => 'gzip, deflate',
        'Accept-Language'           => 'en-US,en;q=0.9',
        'Authorization'             => "$gettrToken",
        'Connection'                => 'keep-alive',
        'env'                       => 'prod',
        'filename'                  => $fileName,
        'Host'                      => 'upload.gettr.com',
        'Iv'                        => 0,
        'Origin'                    => 'https://gettr.com',
        'Referer'                   => "https://gettr.com/",
        'Sec-Fetch-Dest'            => 'empty',
        'Sec-Fetch-Mode'            => 'cors',
        'Sec-Fetch-Site'            => 'same-origin',
        'Sec-GPC'                   => 1,
        'Tus-Resumable'             => '1.0.0',
        'userid'                    => $gettrId,
        'Upload-Length'             => $fileSize,
        'Upload-Metadata'           => $uploadMetadata,
        'User-Agent'                => 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/105.0.0.0 Safari/537.36'
    );
    my $url     = "https://upload.gettr.com/media/big/upload";
    my $request = HTTP::Request::Common::POST(
      $url, @headers
    );
    my $res     = $ua->request($request);
    my $headers = $res->headers()->as_string;
    my @hLines  = split "\n", $headers;
    my $fileLocation;
    for my $hL (@hLines) {
        my ($label, $value) = split ': ', $hL;
        # say "$label -> $value";
        if ($label eq 'Location') {
            $fileLocation = $value;
            last;
        }
    }
    die "Failed to retrieve file location on Gettr for file [$file]" unless $fileLocation;
    return $fileLocation;
}

sub file_type_from_ext {
    my $ext = shift;
    my $fileType;
    if ($ext eq 'mp4') {
        $fileType = 'video/mp4';
    } elsif ($ext eq 'jpg') {
        $fileType = 'image/jpg';
    } elsif ($ext eq '') {

    } else {
        die "Unknown file extension : [$ext]";
    }
    die unless $fileType;
    return $fileType;
}

sub print_telegram_updates {
    for my $channelName (sort keys %messages) {
        for my $messageId (sort{$a <=> $b} keys %{$messages{$channelName}}) {
            my $localFolder = "telegram_data/$channelName/$messageId";
            make_path($localFolder) unless (-d $localFolder);
            unless (-f "$localFolder/message.json") {
                my %obj = %{$messages{$channelName}->{$messageId}};
                open my $out, '>:utf8', "$localFolder/message.json";
                print $out encode_json\%obj;
                close $out;
                if ($replicateTgToGabFeed == 1) {
                    post_on_gab($channelName, $messageId);
                }
                if ($replicateTgToGettrFeed == 1) {
                    post_on_gettr($channelName, $messageId);
                }
                if ($replicateTgToGabGroups == 1) {
                    for my $gabGroupId (@gabGroups) {
                        post_on_gab($channelName, $messageId, $gabGroupId);
                    }
                }
            }
        }
    }
}