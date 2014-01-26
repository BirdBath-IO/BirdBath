package BirdBath::Controller::OAuth2;

use Mojo::Base 'Mojolicious::Controller';
use MojoX::OAuth2::Client;
use Data::Uniqid qw/ luniqid /;

sub choose {
	my $self = shift;

	# TODO choose should probably not be in oauth2 controller
	if(my $invite = $self->session('invite')) {
		$self->stash(invite => $invite);
	}

	$self->render;
}

sub login {
	my $self = shift;
	my $provider = $self->param('provider');
	my $state = luniqid . luniqid;
	$self->session(oauth2 => { provider => $provider, state => $state });
	my $url = $self->oauth2->provider($provider)->get_authorization_url(state => $state);
	$self->redirect_to($url);
}

sub callback {
	my $self = shift;
	my $params = {
		state => $self->req->url->query->param('state'),
		code => $self->req->url->query->param('code'),
	};
	my $provider = $self->session->{oauth2}->{provider};
	$self->stash(provider => $provider);
	my $oauth2 = $self->oauth2->provider($provider);

	$oauth2->receive_code($params)->get_token->on(
		access_denied => sub {
			my ($oauth2, $errors) = @_;
			print "Access Denied:\n";
			use Data::Dumper; print Dumper $errors;
			$self->render(errors => $errors);
		},
		failure => sub {
			my ($oauth2, $error) = @_;
			print "Failure:\n";
			use Data::Dumper; print Dumper $error;
			$self->render(errors => $error);
		},
		success => sub {
			my ($oauth2, $token) = @_;
			$self->session->{oauth2}->{token} = $token;

			my $url = $self->config->{oauth2_providers}->{$provider}->{profile_url} . '?access_token=' . $token->{access_token};
			$self->ua->get($url, { Authorization => 'Bearer ' . $token->{access_token}, Accept => 'application/json' } => sub {
				my ($ua, $tx) = @_;
				use Data::Dumper; print Dumper $tx;
				if($tx->success) {
					my $profile = $self->config->{oauth2_providers}->{$provider}->{transform_profile}->($tx->success->json);
					$profile->{profile} = $tx->success->json;
					$profile->{provider} = $provider;
					$self->users->update({
						provider => $provider,
						id => $profile->{id},
					},$profile,{ upsert => 1} => sub {
						my ($mango, $error, $doc) = @_;
						die("DB error") if $error;
						die("Not updated") if !$doc->{n};
						delete $profile->{profile};
						$self->session->{user} = $profile;
						$self->redirect_to('/');
					});
				} else {
					print "Error getting profile:\n";
					use Data::Dumper; print Dumper $tx->error;
					$self->render(errors => $tx->error);
				}
			});
		}
	)->execute;
	$self->render_later;
}

1;