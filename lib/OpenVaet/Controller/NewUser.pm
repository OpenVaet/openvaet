package OpenVaet::Controller::NewUser;
use Mojo::Base 'Mojolicious::Controller';
use Mojo::Log;
use JSON;
use Scalar::Util qw(looks_like_number);
use Data::Printer;
use FindBin;
use lib "$FindBin::Bin/../lib";
use config;

sub create_user {
    my $self        = shift;
    my $userMail    = $self->param('userMail');
    my $password    = $self->param('password');
    my $currentLanguage   = $self->param('currentLanguage');
    say "userMail  : $userMail";
    say "password  : $password";
    say "currentLanguage : $currentLanguage";

    # Initiating response.
    my %json         = ();
    my ($referrer, $message, $status, $token, $emailVerification);
    if (!$currentLanguage || !$userMail || !$password) {
        $status  = 'ko';
        if ($currentLanguage eq 'en') {
            $message = 'Mandatory Data Missing';
        } else {
            $message = 'Données obligatoires manquantes';
        }
    } else {
        # Verifies the password fits the front constrains.
        my $passIsValid  = $self->verify_password($password);
        if ($passIsValid ne 'ok') {
            $status  = 'ko';
            $message = $passIsValid;
        } else {
            use Email::Valid;

            # Verify if the mail format is valid.
            unless( Email::Valid->address($userMail) ) {
                $status  = 'ko';
                if ($currentLanguage eq 'en') {
                    $message = 'Invalid Mail Format';
                } else {
                    $message = 'Format courriel invalide';
                }
            } else {

                # Verify that the user isn't already known.
                my $uTb = $self->dbh->selectrow_hashref("SELECT id FROM user WHERE email = ?", undef, $userMail);
                if ($uTb) {
                    $status   = 'ko';
                    if ($currentLanguage eq 'en') {
                        $message  = 'This user already exists. Please login instead.';
                    } else {
                        $message  = 'Cet utilisateur existe déjà. Veuillez vous connecter';
                    }
                } else {
                    $status   = 'ok';
                    $referrer = $self->session->{referrer};
                    $token    = $self->gen_token();
                    $emailVerification = 0;
                    $self->session->{token}             = $token;
                    $self->session->{currentLanguage}   = $currentLanguage;
                    $self->session->{emailVerification} = $emailVerification;
                    $self->session->{name}              = $userMail;

                    # Creating new user.
                    my $cryptedPass         = $self->bcrypt( $password );
                    my @chars               = (0..9);
                    my $emailVerificationCode = join " ", map { $chars[rand @chars] } 1 .. 6;
                    my $eVCSaved            = $emailVerificationCode;
                    $eVCSaved               =~ s/ //g;
                    my $sth                 = $self->dbh->prepare("INSERT INTO user (email, emailVerificationCode, password, token) VALUES (?, ?, ?, ?)");
                    $sth->execute($userMail, $eVCSaved, $cryptedPass, $token) or die $sth->err();
                    forward_email_confirm($userMail, $emailVerificationCode, $currentLanguage);
                }
            }
        }
    }

    $json{'emailVerification'} = $emailVerification;
    $json{'message'}           = $message;
    $json{'token'}             = $token;
    $json{'status'}            = $status;
    $json{'referrer'}          = $referrer;


    $self->render(json => \%json);
}

sub forward_email_confirm {
    my ($userMail, $emailVerificationCode, $currentLanguage) = @_;
    my $serverMailAddress = $config{'serverMailAddress'} // die;
    say "Mailing [$userMail] : [Saisissez le code suivant pour valider votre email : $emailVerificationCode.]";
    if ($currentLanguage eq 'en') {
        system("
        (
        echo \"From: $serverMailAddress\";
        echo \"To: $userMail\";
        echo \"Subject: OpenVAET Code : $emailVerificationCode\";
        echo \"Content-Type: text/html\";
        echo \"MIME-Version: 1.0\";
        echo \"\";
        echo \"<html>
        <body>
        <div style=\\\"
            width: 300px;
            height: 300px;
            text-align:center;
            \\\">
            Please enter the following code to confirm your email<br><b>$emailVerificationCode</b>
        </div>
        </body>
        </html>\";
        ) | sendmail -t
        ");
    } else {
        system("
        (
        echo \"From: $serverMailAddress\";
        echo \"To: $userMail\";
        echo \"Subject: Code OpenVAET : $emailVerificationCode\";
        echo \"Content-Type: text/html\";
        echo \"MIME-Version: 1.0\";
        echo \"\";
        echo \"<html>
        <body>
        <div style=\\\"
            width: 300px;
            height: 300px;
            text-align:center;
            \\\">
            Veuillez saisir le code suivant pour valider votre courriel<br><b>$emailVerificationCode</b>
        </div>
        </body>
        </html>\";
        ) | sendmail -t
        ");
    }
}

sub load_email_confirm {
    my $self          = shift;
    my $userMail      = $self->param("userMail");
    my $currentLanguage       = $self->param('currentLanguage');

    if (!$userMail) {
        $self->render(
            text => 'mandatoryDataMissing'
        );
    }

    $self->render(
        userMail  => $userMail,
        currentLanguage  => $currentLanguage
    );
}

sub confirm_email {
    my $self                  = shift;
    my $userMail              = $self->param('userMail');
    my $currentLanguage       = $self->param('currentLanguage');
    my $emailVerificationCode = $self->param('emailVerificationCode');
    say "userMail              : $userMail";
    say "emailVerificationCode : $emailVerificationCode";
    my ($message, $status);
    if (!$userMail || !$emailVerificationCode || !$currentLanguage) {
        $status  = 'ko';
        if ($currentLanguage eq 'en') {
            $message = 'Mandatory Data Missing';
        } else {
            $message = 'Données obligatoires manquantes';
        }
    } else {

        # Verifies the code fits the expected format.
        my $emailVerificationCodeLength = length $emailVerificationCode;
        if ($emailVerificationCodeLength != 6 || !looks_like_number $emailVerificationCode) {
            $status  = 'ko';
            if ($currentLanguage eq 'en') {
                $message = 'Incorrect Code Format';
            } else {
                $message = 'Format du code incorrect';
            }
        } else {
            # Verifies the token & verification code are fitting the ones expected in the DB.
            my $uTb  = $self->dbh->selectrow_hashref("SELECT id as userId, emailVerificationCode, emailVerification FROM user WHERE email = ?", undef, $userMail);
            if (!$uTb) {
                $status  = 'ko';
                if ($currentLanguage eq 'en') {
                    $message = 'User Unknown';
                } else {
                    $message = 'Utilisateur Inconnu';
                }
            } else {
                my $emailVerification = %$uTb{'emailVerification'};
                $emailVerification    = unpack("N", pack("B32", substr("0" x 32 . $emailVerification, -32)));
                if ($emailVerification) {
                    $status  = 'ko';
                    if ($currentLanguage eq 'en') {
                        $message = 'Email Already Confirmed';
                    } else {
                        $message = 'Courriel déjà confirmé';
                    }
                } else {
                    if (%$uTb{'emailVerificationCode'} ne $emailVerificationCode) {
                        $status  = 'ko';
                        if ($currentLanguage eq 'en') {
                            $message = 'Incorrect Code, please verify your mails';
                        } else {
                            $message = 'Code Incorrect, veuillez vérifier vos courriels';
                        }
                    } else {
                        my $userId = %$uTb{'userId'};
                        $status    = 'ok';
                        my $sth    = $self->dbh->prepare("UPDATE user SET emailVerification = 1, emailVerificationTimestamp = UNIX_TIMESTAMP() WHERE id = $userId");
                        $sth->execute() or die $sth->err();
                        $self->session->{emailVerification} = 1;
                    }
                }
            }
        }
    }


    my %json          = ();
    $json{'message'}  = $message;
    $json{'status'}   = $status;
    p%json;

    $self->render(json => \%json);
}

1;