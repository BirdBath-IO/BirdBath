package BirdBath::Controller::Manage;

use Mojo::Base 'Mojolicious::Controller';

use Mango::BSON qw/ bson_oid bson_time/;
use Net::Twitter;

sub welcome {
  my $self = shift;

  $self->render();
}

sub request {
	my $self = shift;

	my $username = $self->param('username');
	die("No username") if !$username;

	$username = substr($username, 1) if substr($username, 0, 1) eq '@';

	# Needs to lookup account again, its not user-specific like the bridge
	$self->app->accounts->find_one({screen_name_lc => lc($username)} => sub {
		my ($mango, $error, $doc) = @_;

		if($error) {
			$self->log->debug("Database error: $error");
			$self->render_exception("Database error");
			return 0;
		}

		if(!$doc) {
			my $suggest = "\@$username Have you seen \@BirdBath_SM - https://github.com/ian-kent/BirdBath";
			my $link = "<a href=\"https://twitter.com/intent/tweet?source=webclient&text=$suggest\">";
			$link .= "Why not ask them to join?";
			$link .= "</a>";
			$self->render(json => { error => "Twitter account not yet registered with BirdBath - $link"});
			return 0;
		}

		for my $u (@{$doc->{users}}) {
			if($u->{id} eq $self->session->{user}->{id} && 
			   $u->{provider} eq $self->session->{user}->{provider}) {
				$self->render(json => { error => "You already have access to this account"});
				return 0;
			}
		}

		$self->app->accounts->update({screen_name_lc => lc($username)}, {
			'$addToSet' => {
				'requests' => {
					provider => $self->session->{user}->{provider},
				    id => $self->session->{user}->{id},
				    avatar => $self->session->{user}->{avatar},
				    name => $self->session->{user}->{name},
				    username => $self->session->{user}->{username},
				}
			}
		} => sub {
			my ($mango, $error, $doc) = @_;
			
			if($error) {
				$self->log->debug("Database error: $error");
				$self->render_exception("Database error");
				return 0;
			}

			if(!$doc->{n}) {
				$self->render(json => { error => "Not updated" });
				return 0;
			}

			if(lc($self->session->{invite}) eq lc($username)) {
				delete $self->session->{invite};
			}

			return $self->render(json => { ok => 1 });
		});
	});

	$self->render_later;
}

sub accept_user {
	my $self = shift;

	my $provider = $self->req->json->{provider};
	my $id = $self->req->json->{id};
	my $account = $self->req->json->{account};

	$self->app->accounts->find_one({screen_name_lc => lc($account)} => sub {
		my ($mango, $error, $doc) = @_;
		
		if($error) {
			$self->log->debug("Database error: $error");
			$self->render_exception("Database error");
			return 0;
		}

		if(!$doc) {
			$self->render(json => { error => "Not found" });
			return 0;
		}

		my $user;
		for my $u (@{$doc->{requests}}) {
			if($u->{id} eq $id && $u->{provider} eq $provider) {
				$user = $u;
				last;
			}
		}

		if(!$user) {
			$self->render(json => { error => "User not found" });
			return 0;
		}

		$self->app->accounts->update({screen_name_lc => lc($account)}, {
			'$addToSet' => {
				'users' => {
					provider => $user->{provider},
				    id => $user->{id},
				    avatar => $user->{avatar},
				    name => $user->{name},
				    username => $user->{username},
				    role => 'none',
				}
			},
			'$pull' => {
				'requests' => {
					provider => $user->{provider},
				    id => $user->{id},
				    avatar => $user->{avatar},
				    name => $user->{name},
				    username => $user->{username},
				}
			}
		} => sub {
			my ($mango, $error, $doc) = @_;
			
			if($error) {
				$self->log->debug("Database error: $error");
				$self->render_exception("Database error");
				return 0;
			}

			if(!$doc->{n}) {
				$self->render(json => { error => "Not updated" });
				return 0;
			}

			return $self->render(json => { ok => 1 });
		});
	});
}

sub reject_user {
	my $self = shift;

	my $provider = $self->req->json->{provider};
	my $id = $self->req->json->{id};
	my $account = $self->req->json->{account};

	$self->app->accounts->find_one({screen_name_lc => lc($account)} => sub {
		my ($mango, $error, $doc) = @_;
		
		if($error) {
			$self->log->debug("Database error: $error");
			$self->render_exception("Database error");
			return 0;
		}

		if(!$doc) {
			$self->render(json => { error => "Not found" });
			return 0;
		}

		my $user;
		for my $u (@{$doc->{requests}}) {
			if($u->{id} eq $id && $u->{provider} eq $provider) {
				$user = $u;
				last;
			}
		}

		if(!$user) {
			$self->render(json => { error => "User not found" });
			return 0;
		}

		$self->app->accounts->update({screen_name_lc => lc($account)}, {
			'$pull' => {
				'requests' => {
					provider => $user->{provider},
				    id => $user->{id},
				    avatar => $user->{avatar},
				    name => $user->{name},
				    username => $user->{username},
				}
			}
		} => sub {
			my ($mango, $error, $doc) = @_;
			
			if($error) {
				$self->log->debug("Database error: $error");
				$self->render_exception("Database error");
				return 0;
			}

			if(!$doc->{n}) {
				$self->render(json => { error => "Not updated" });
				return 0;
			}

			return $self->render(json => { ok => 1 });
		});
	});
}

sub remove_user {
	my $self = shift;

	my $account = $self->req->json->{account};
	my $provider = $self->req->json->{provider};
	my $id = $self->req->json->{id};

	$self->app->accounts->find_one({
		screen_name_lc => lc($account),
		'users.provider' => $provider,
		'users.id' => $id
	} => sub {
		my ($mango, $error, $doc) = @_;
		
		if($error) {
			$self->log->debug("Database error: $error");
			$self->render_exception("Database error");
			return 0;
		}

		if(!$doc) {
			$self->render(json => { error => "Not found" });
			return 0;
		}

		my $user;
		for my $u (@{$doc->{users}}) {
			if($u->{id} eq $id && $u->{provider} eq $provider) {
				$user = $u;
				last;
			}
		}

		if(!$user) {
			$self->render(json => { error => "User not found" });
			return 0;
		}

		$self->app->accounts->update({
			screen_name_lc => lc($account),
			'users' => $user
		}, {
			'$pull' => {
				'users' => $user
			}
		} => sub {
			my ($mango, $error, $doc) = @_;
			
			if($error) {
				$self->log->debug("Database error: $error");
				$self->render_exception("Database error");
				return 0;
			}

			if(!$doc->{n}) {
				$self->render(json => { error => "Not updated" });
				return 0;
			}

			return $self->render(json => { ok => 1 });
		});
	});

	$self->render_later;
}

sub remove_account {
	my $self = shift;

	my $account = $self->req->json->{account};

	$self->app->accounts->find_one({
		screen_name_lc => lc($account),
		'$or' => [
			{
				'users.provider' => $self->session->{user}->{provider},
				'users.id' => $self->session->{user}->{id}
			},{
				'requests.provider' => $self->session->{user}->{provider},
				'requests.id' => $self->session->{user}->{id}
			}
		]
	} => sub {
		my ($mango, $error, $doc) = @_;
		
		if($error) {
			$self->log->debug("Database error: $error");
			$self->render_exception("Database error");
			return 0;
		}

		if(!$doc) {
			$self->render(json => { error => "Not found" });
			return 0;
		}

		my $user;
		for my $u (@{$doc->{users}}) {
			if($u->{id} eq $self->session->{user}->{id} && $u->{provider} eq $self->session->{user}->{provider}) {
				$user = $u;
				last;
			}
		}

		my $request;
		if(!$user) {
			for my $u (@{$doc->{requests}}) {
				if($u->{id} eq $self->session->{user}->{id} && $u->{provider} eq $self->session->{user}->{provider}) {
					$request = $u;
					last;
				}
			}
		}

		if(!$user && !$request) {
			$self->render(json => { error => "Request not found" });
			return 0;
		}

		my %args = ();
		$args{users} = $user if $user;
		$args{requests} = $request if $request;

		$self->app->accounts->update({
			screen_name_lc => lc($account),
			%args
		}, {
			'$pull' => {
				%args
			}
		} => sub {
			my ($mango, $error, $doc) = @_;
			
			if($error) {
				$self->log->debug("Database error: $error");
				$self->render_exception("Database error");
				return 0;
			}

			if(!$doc->{n}) {
				$self->render(json => { error => "Not updated" });
				return 0;
			}

			return $self->render(json => { ok => 1 });
		});
	});

	$self->render_later;
}

sub save_user {
	my $self = shift;

	my $provider = $self->req->json->{provider};
	my $id = $self->req->json->{id};
	my $account = $self->req->json->{account};
	my $role = $self->req->json->{role};

	$self->app->accounts->find_one({screen_name_lc => lc($account)} => sub {
		my ($mango, $error, $doc) = @_;
		
		if($error) {
			$self->log->debug("Database error: $error");
			$self->render_exception("Database error");
			return 0;
		}

		if(!$doc) {
			$self->render(json => { error => "Not found" });
			return 0;
		}

		my $user;
		for my $u (@{$doc->{users}}) {
			if($u->{id} eq $id && $u->{provider} eq $provider) {
				$user = $u;
				last;
			}
		}

		if(!$user) {
			$self->render(json => { error => "User not found" });
			return 0;
		}

		$self->app->accounts->update({
			screen_name_lc => lc($account),
			'users' => $user
		}, {
			'$set' => {
				'users.$.role' => $role
			}
		} => sub {
			my ($mango, $error, $doc) = @_;
			
			if($error) {
				$self->log->debug("Database error: $error");
				$self->render_exception("Database error");
				return 0;
			}

			if(!$doc->{n}) {
				$self->render(json => { error => "Not updated" });
				return 0;
			}

			return $self->render(json => { ok => 1 });
		});
	});

	$self->render_later;
}

1;
