package OpenVaet::Controller::Login;
use Mojo::Base 'Mojolicious::Controller';
use Mojo::Log;
use Data::Printer;
use JSON;
use FindBin;
use lib "$FindBin::Bin/../lib";

sub open_login_tab {
    my $self = shift;
    my $currentLanguage = $self->param('currentLanguage');
    say "open_login_tab ...";
    say "currentLanguage : $currentLanguage";

    my $tabName = $self->param("tabName");
    if (!$tabName || ($tabName ne 'login' || $tabName ne 'signout')) {
        $self->render(text => 'Unauthorized')
    }

    say "tabName : $tabName";

    $self->render(
        tabName => $tabName,
        currentLanguage => $currentLanguage
    );
}

sub login {
    my $self      = shift;

    my $userMail  = $self->session('userMail');
    my $currentLanguage = $self->param('currentLanguage');
    my $token     = $self->session('token');

    my $referrer  = $self->req->headers->referrer || '';
    if (!$self->session->{referrer} &&  # Referrer is not already set
        $referrer &&                    # Referrer is not null
        $referrer !~ m{/login$}) {      # Referrer is not the login page
        $self->session->{referrer} = $referrer;
    }

    $self->render(
        userMail  => $userMail,
        currentLanguage => $currentLanguage,
        token     => $token
    );
}

sub do_login {
    my $self          = shift;
    my $userMail      = $self->param('userMail');
    my $password      = $self->param('password');
    my $currentLanguage = $self->param('currentLanguage');
    say "userMail  : $userMail";
    say "password  : $password";
    say "currentLanguage : $currentLanguage";
    my %json       = ();
    my ($referrer, $message, $status, $token, $emailVerification);
    if ($userMail && $password && $currentLanguage) {
        my $connection = $self->connect_user($userMail, $password, $currentLanguage);
        if ($connection->{code} == 0) {
            $token    = $self->session->{token};
            $referrer = delete $self->session->{referrer};
            $emailVerification = $connection->{emailVerification};
            $status   = 'ok';
        } else {
            if ($currentLanguage eq 'en') {
                $message = 'Incorrect Credentials';
            } else {
                $message = 'Identifiants Incorrects';
            }
            $status  = 'ko';
        }
    } else {
        if ($currentLanguage eq 'en') {
            $message = 'Mandatory data missing';
        } else {
            $message = 'Données obligatoires manquantes';
        }
        $status  = 'ko';
    }
    $json{'emailVerification'} = $emailVerification;
    $json{'message'}           = $message;
    $json{'token'}             = $token;
    $json{'status'}            = $status;
    $json{'referrer'}          = $referrer;

    p%json;

    $self->render(json => \%json);
}

# Logs a user out and redirects to index
sub logout {
    my $self         = shift;
    my ($userMail,
        $token,
        $currentLanguage);
    my $json         = $self->req->json;
    if ($json) {
        $userMail    = %$json{'userMail'};
        $token       = %$json{'token'};
        $currentLanguage   = %$json{'currentLanguage'};
    }
    my ($message, $status);
    if (!$userMail || !$token || !$currentLanguage) {
        $message = 'mandatoryDataMissing';
        $status  = 'ko';
    } else {
        my $disconnection = $self->disconnect_user($userMail, $token, $currentLanguage);
        if ($disconnection->{code} == 0) {
            $status  = 'ok';
        } else {
            $status  = 'ko';
            $message = 'permissionNotGranted';
        }
    }
    $self->session->{token}             = undef;
    $self->session->{emailVerification} = undef;
    $self->session->{name}              = undef;
    $self->session(expires => 1);

    my %json         = ();
    $json{'message'} = $message;
    $json{'status'}  = $status;

    $self->render(json => \%json);
}

1;