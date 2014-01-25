package BirdBath::OAuth2;

use Mojo::Base 'Mojolicious::Controller';
use MojoX::OAuth2::Client;
use Data::Uniqid qw/ luniqid /;

sub choose {
	my $self = shift;
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
			$self->render(errors => $errors);
		},
		failure => sub {
			my ($oauth2, $error) = @_;
			$self->render(errors => $error);
		},
		success => sub {
			my ($oauth2, $token) = @_;
			$self->session->{oauth2}->{token} = $token;

			my $url = $self->config->{oauth2_providers}->{$provider}->{profile_url} . '?access_token=' . $token->{access_token};
			$self->ua->get($url, { Accept => 'application/json' } => sub {
				my ($ua, $tx) = @_;
				if($tx->success) {
					$self->users->update({
						provider => $provider,
						id => $tx->success->json->{id},
					},{
						provider => $provider,
						id => $tx->success->json->{id},
						avatar => $tx->success->json->{avatar_url},
						name => $tx->success->json->{name},
						username => $tx->success->json->{login},
						profile => $tx->success->json,
					},{ upsert => 1} => sub {
						my ($mango, $error, $doc) = @_;
						die("DB error") if $error;
						die("Not updated") if !$doc->{n};
						# TODO this is probably github specific
						$self->session->{user} = {
							provider => $provider,
							id => $tx->success->json->{id},
							avatar => $tx->success->json->{avatar_url},
							name => $tx->success->json->{name},
							username => $tx->success->json->{login},
						};
						$self->redirect_to('/');
					});
				} else {
					$self->render(errors => $tx->error);
				}
			});
		}
	)->execute;
	$self->render_later;
}

1;