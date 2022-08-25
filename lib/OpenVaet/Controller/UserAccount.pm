package OpenVaet::Controller::UserAccount;
use Mojo::Base 'Mojolicious::Controller';
use Mojo::Log;
use FindBin;
use lib "$FindBin::Bin/../lib";
use config;

use Data::Printer;

sub user_security {
    my $self = shift;

    my $currentLanguage = $self->param('currentLanguage') // 'fr';
    my $userMail        = $self->session('userMail');

    unless ($userMail) {
        $self->render(text => 'You must be connected to access this page.');
    } else {
        # Loggin session if unknown.
        session::session_from_self($self);

        my %languages = ();
        $languages{'fr'} = 'French';
        $languages{'en'} = 'English';

        $self->render(
            currentLanguage => $currentLanguage,
            userMail => $userMail,
            languages => \%languages
        );
    }
}

sub change_password {
    my $self            = shift;
    my $userId          = $self->session('userId');
    my $currentLanguage = $self->param('currentLanguage');
    my $currentPassword = $self->param('currentPassword');
    say "currentPassword : $currentPassword";
    my $password        = $self->param('password');
    my ($message, $status);
    if (!$currentPassword || !$password || !$userId || !$currentLanguage) {
        if ($currentLanguage eq 'en') {
            $message = 'Mandatory Data Missing';
        } else {
            $message = 'Données obligatoires manquantes';
        }
        $status  = 'ko';
    } else {
        my $userData = $self->dbh->selectrow_hashref("SELECT password FROM user WHERE id = ?", undef, $userId);
        # p$userData;
        my $dbPassword = %$userData{'password'};
        say "dbPassword : $dbPassword";
        if (!$self->bcrypt_validate( $currentPassword, $dbPassword)) {
            $status  = 'ko';
            if ($currentLanguage eq 'en') {
                $message = 'Incorrect Current Password';
            } else {
                $message = 'Mot de passe actuel incorrect';
            }
        } else {
            my $passIsValid = $self->verify_password($password);
            if ($passIsValid ne 'ok') {
                $status  = 'ko';
                $message = $passIsValid;
            } else {
                $status  = 'ok';
                my $cryptedPass = $self->bcrypt( $password );
                $self->dbh->do('UPDATE user SET password = ?
                                   WHERE id = ?',
                                  undef, $cryptedPass, $userId);
                # $self->session->{token}             = undef;
                # $self->session->{emailVerification} = undef;
                # $self->session->{name}              = undef;
                # $self->session(expires => 1);
            }
        }
    }

    my %json         = ();
    $json{'message'} = $message;
    $json{'status'}  = $status;

    p%json;

    $self->render(json => \%json);
}

sub forgot_password {
    my $self     = shift;
    my $serverMailAddress = $config{'serverMailAddress'} // die;
    my $currentLanguage = $config{'currentLanguage'} // die;
    my $userMail = $self->param('userMail');

    # Verifying mail validity ; sending code if valid request.
    if ($userMail) {

        my $uTb = $self->dbh->selectrow_hashref("SELECT passwordReinitCode, passwordReinitAttempts, passwordReinitTimestamp, id as userId FROM user WHERE email = ?", undef, $userMail);
        p$uTb;
        if ($uTb) {
            my $passwordReinitTimestamp = %$uTb{'passwordReinitTimestamp'};
            my $passwordReinitAttempts  = %$uTb{'passwordReinitAttempts'};
            my $userId                  = %$uTb{'userId'};
            my $currentTimestamp        = time::current_timestamp();
            if (!$passwordReinitTimestamp || ($passwordReinitTimestamp && ($currentTimestamp > $passwordReinitTimestamp))) {
                say "Timestamp & mail valid. Reinitiating password for user [$userMail].";
                my @chars              = (0..9);
                my $passwordReinitCode = join " ", map { $chars[rand @chars] } 1 .. 6;
                $currentTimestamp      = $currentTimestamp + 900; # One new code per 15 minutes by default.
                say "Mailing [$userMail] : [Saisissez le code suivant pour réinitialiser votre mot de passe : $passwordReinitCode.]";
                if ($currentLanguage eq 'en') {
                    system("
                    (
                    echo \"From: $serverMailAddress\";
                    echo \"To: $userMail\";
                    echo \"Subject: OpenVAET Code : $passwordReinitCode\";
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
                        Please enter the following code to reset your password<br><b>$passwordReinitCode</b>
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
                    echo \"Subject: Code OpenVAET : $passwordReinitCode\";
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
                        Saisissez le code suivant pour réinitialiser votre mot de passe<br><b>$passwordReinitCode</b>
                    </div>
                    </body>
                    </html>\";
                    ) | sendmail -t
                    ");
                }
                $passwordReinitCode =~ s/ //g;
                my $sth = $self->dbh->prepare("UPDATE user SET passwordReinitCode = ?, passwordReinitAttempts = 0, passwordReinitTimestamp = $currentTimestamp WHERE id = $userId");
                $sth->execute($passwordReinitCode);
            }
        }
    }


    $self->render(
        userMail => $userMail
    );
}

sub confirm_password_change {
    my $self = shift;
    my $currentLanguage     = $self->param('currentLanguage');
    my $userMail            = $self->param('userMail');
    my $passwordReinitCode  = $self->param('passwordReinitCode');
    my $password            = $self->param('password');
    my ($message, $status);
    my $passwordReinitAttempts = 0;
    my %json       = ();
    if (!$userMail || !$passwordReinitCode || !$userMail) {
        $message   = 'mandatoryDataMissing';
        $status    = 'ko';
    } else {

        # Verifies that the code matches the DB one.
        my $uTb = $self->dbh->selectrow_hashref("SELECT id as userId, passwordReinitCode, passwordReinitAttempts, passwordReinitTimestamp, passwordReinitFailedAttemtps FROM user WHERE email = ?", undef, $userMail);
        if (!$uTb || ($uTb && (!%$uTb{'passwordReinitCode'}))) {
            $message = 'mandatoryDataMissing';
            $status  = 'ko';
        } else {
            $passwordReinitAttempts = %$uTb{'passwordReinitAttempts'};
            if ($passwordReinitAttempts <= 5) {
                if ($passwordReinitCode eq %$uTb{'passwordReinitCode'}) {
                    if ($password) {
                        say "password: $password";
                        # Verifies password and proceeds if valid.
                        my $passIsValid = $self->verify_password($password);
                        if ($passIsValid ne 'ok') {
                            $status  = 'ko';
                            $message = $passIsValid;
                        } else {
                            $status  = 'ok';
                            my $cryptedPass = $self->bcrypt( $password );
                            $self->dbh->do('UPDATE user SET password = ?, passwordReinitAttempts = 0, passwordReinitTimestamp = NULL, passwordReinitFailedAttemtps = 0, passwordReinitCode = NULL
                                               WHERE email = ?',
                                              undef, $cryptedPass, $userMail);
                        }
                    } else {
                        # Simply returns that the code is valid.
                        $status  = 'ok';
                    }
                } else {
                    if ($currentLanguage eq 'en') {
                        $message = 'Incorrect Code';
                    } elsif ($currentLanguage eq 'fr') {
                        $message = 'Code Incorrect';
                    }
                    $status  = 'ko';
                    $passwordReinitAttempts++;
                    if ($passwordReinitAttempts > 5) {
                        my $passwordReinitTimestamp = %$uTb{'passwordReinitTimestamp'};
                        my $passwordReinitFailedAttemtps = %$uTb{'passwordReinitFailedAttemtps'};
                        my $userId = %$uTb{'userId'};
                        $passwordReinitFailedAttemtps++;
                        $passwordReinitTimestamp = ($passwordReinitTimestamp + (3600 ** $passwordReinitFailedAttemtps));
                        my $sth = $self->prepare("UPDATE user SET passwordReinitAttempts = 0, passwordReinitTimestamp = $passwordReinitTimestamp, passwordReinitFailedAttemtps = $passwordReinitFailedAttemtps, passwordReinitCode = NULL WHERE id = $userId");
                        $sth->execute() or die $sth->err();
                    }
                }
            } else {
                $message = 'attemptsLimitsReached';
                $status  = 'ko';
            }
        }
    }

    $json{'passwordReinitAttempts'} = $passwordReinitAttempts;
    $json{'message'}                = $message;
    $json{'status'}                 = $status;
    p%json;
    $self->render(json => \%json);
}

1;