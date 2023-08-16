package OpenVaet::Controller::Substack;
use Mojo::Base 'Mojolicious::Controller';
use Mojo::Log;
use JSON;
use Data::Printer;
use Math::Round qw(nearest);
use File::Path qw(make_path);
use Digest::MD5  qw(md5 md5_hex md5_base64);
use FindBin;
use lib "$FindBin::Bin/../lib";
use File::Path qw(make_path);
use session;

sub substack {
    my $self   = shift;
    my $userId = $self->session('userId');

    my $currentLanguage = 'en';

    # Loggin session if unknown.
    session::session_from_self($self);

    my %languages = ();
    $languages{'fr'} = 'French';
    $languages{'en'} = 'English';

    $self->render(
        userId          => $userId,
        currentLanguage => $currentLanguage,
        languages       => \%languages
    );
}

sub minify_url {
    my $self            = shift;
    my $userId          = $self->session('userId')    // die;
    my $urlToMinify     = $self->param('urlToMinify') // die;
    my $currentLanguage = 'en';

    my %languages       = ();
    $languages{'fr'}    = 'French';
    $languages{'en'}    = 'English';

    my %response        = ();
    $response{'status'} = 'ok';
    $response{'error'}  = '';

    say "urlToMinify : $urlToMinify";
    use HTTP::Cookies;
    use HTML::Tree;
    use LWP::UserAgent;
    use LWP::Simple;
    use HTTP::Cookies qw();
    use HTTP::Request::Common qw(POST OPTIONS);
    use HTTP::Headers;

    my $urlMd5;
    if ($urlToMinify !~ /substack/) {
        $response{'status'} = 'ko';
        $response{'error'}  = 'L\'URL doit être un sous-domaine de Substack.';
    } else {
        ($urlToMinify) = split '\?', $urlToMinify if $urlToMinify =~ /\?/;
        $urlMd5 = md5_hex($urlToMinify);
        unless (-d "public/substack/$urlMd5") {
            make_path("public/substack/$urlMd5");
            make_path("templates/c$urlMd5");
        }
            
        my $ua                        = LWP::UserAgent->new
        (
            timeout                  => 30,
            cookie_jar               => HTTP::Cookies->new,
            agent                    => 'Mozilla/5.0 (Windows NT 6.3; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/77.0.3865.90 Safari/537.36'
        );
        my $res     = $ua->get($urlToMinify);
        my $content = $res->decoded_content;
        my $tree    = HTML::Tree->new();
        $tree->parse($content);
        my $twitterImage   = $tree->look_down(name=>"twitter:image");
        $twitterImage      = $twitterImage->attr_get_i('content');
        my $twitterContent = $tree->look_down(name=>"twitter:description");
        $twitterContent    = $twitterContent->attr_get_i('content');
        my $twitterTittle  = $tree->find('title');
        $twitterTittle     = $twitterTittle->as_trimmed_text;
        $twitterTittle =~ s/\'/\\\'/g;


        my ($fileType)     = $twitterImage =~ /\.(\w+)$/;
        my $response       = $ua->get($twitterImage, ':content_file' => "public/substack/$urlMd5/preview.$fileType");
        say "urlMd5         : $urlMd5";
        say "urlToMinify    : $urlToMinify";
        say "twitterTittle  : $twitterTittle";
        say "twitterImage   : $twitterImage";
        say "twitterContent : $twitterContent";
        say "File type      : $fileType";

        unless ($response->is_success) {
            die $response->status_line;
        }

        my $controller = set_controller($urlMd5);
        open my $outC, '>:utf8', "lib/OpenVaet/Controller/C$urlMd5.pm" or die $!;
        print $outC $controller;
        close $outC;

        my $html  = "\% title '$twitterTittle';
<head>

    <script type=\"text/javascript\" src=\"/js/jquery.js\"></script>
    <!-- Primary Meta Tags -->
    <meta name=\"title\" content=\"$twitterTittle\">
    <meta name=\"description\" content=\"$twitterContent\">

    <!-- Open Graph / Facebook -->
    <meta property=\"og:type\" content=\"website\">
    <meta property=\"og:url\" content=\"$urlToMinify\">
    <meta property=\"og:title\" content=\"$twitterTittle\">
    <meta property=\"og:description\" content=\"$twitterContent\">
    <meta property=\"og:image\" content=\"https://openvaet.org/substack/$urlMd5/preview.$fileType\">

    <!-- Twitter -->
    <meta property=\"twitter:card\" content=\"summary_large_image\">
    <meta property=\"twitter:url\" content=\"$urlToMinify\">
    <meta property=\"twitter:title\" content=\"$twitterTittle\">
    <meta property=\"twitter:description\" content=\"$twitterContent\">
    <meta property=\"twitter:image\" content=\"https://openvaet.org/substack/$urlMd5/preview.$fileType\">
</head>

<script>
    \$( document ).ready(function() {
        window.location.href = '$urlToMinify';
    });
</script>
        ";  
        open my $outH, '>:utf8', "templates/c$urlMd5/f$urlMd5.html.ep" or die $!;
        print $outH $html;
        close $outH;

        my $mainController = 'lib/OpenVaet.pm';
        my $mainControllerContent;
        open my $in, '<', $mainController;
        while (<$in>) {
            chomp $_;
            $mainControllerContent .= "$_\n";
            if ($_ =~ /START SUBSTACK URLS/) {
                $mainControllerContent .= "    \$r->get('/f$urlMd5')->to('C$urlMd5#f$urlMd5');\n";
            }
        }
        close $in;
        open my $out, '>', $mainController or die $!;
        say $out $mainControllerContent;
        close $out;
    }

    system("sudo hypnotoad script/openvaet");

    $self->render(
        urlMd5 => $urlMd5
    );
}

sub set_controller {
    my $urlMd5 = shift;
    return "package OpenVaet::Controller::C$urlMd5;
use Mojo::Base 'Mojolicious::Controller';
use Mojo::Log;
use JSON;
use Data::Printer;
use FindBin;
use lib \"\$FindBin::Bin/../lib\";
use session;

sub f$urlMd5 {
    my \$self = shift;

    # Loggin session if unknown.
    session::session_from_self(\$self);

    \$self->render(
    );
}

1;";
}

1;