package BirdBath::Home;

use Mojo::Base 'Mojolicious::Controller';

use Mango::BSON qw/ bson_oid bson_time/;
use Net::Twitter;

sub welcome {
  my $self = shift;

  $self->render(user => $self->session->{user});
}

sub logout {
	my $self = shift;
	$self->session(expires => -1);
	$self->redirect_to('/');
}

sub accounts {
	my $self = shift;

	my $cursor = $self->app->accounts->find;
	$cursor->all(sub {
		my ($mango, $error, $docs) = @_;

		die("DB error") if $error;

		my @accounts;
		for my $doc (@$docs) {
			push @accounts, {
				screen_name => $doc->{screen_name},
				profile => {
					name => $doc->{profile}->{name},
					image_url => $doc->{profile}->{profile_image_url},
				}
			};
		}

		$self->render(json => \@accounts);
	});

	$self->render_later;
}

sub tweets {
	my $self = shift;

	my $cursor = $self->app->tweets->find->sort({created => -1});
	$cursor->all(sub {
		my ($mango, $error, $docs) = @_;

		die("DB error") if $error;

		for my $doc (@$docs) {
			if($doc->{edits}) {
				$doc->{last_edit} = $doc->{edits}->[-1];
			}
		}

		$self->render(json => $docs);
	});

	$self->render_later;
}

sub tweet {
	my $self = shift;

	my $message = $self->req->json->{message};
	my $account = $self->req->json->{account};

	$self->app->accounts->find_one({ screen_name => $account } => sub {
		my ($mango, $error, $doc) = @_;
		die("DB error") if $error;
		die("Not found") if !$doc;

		$self->app->tweets->insert({
			user => {
				id => $self->session->{user}->{id},
				gravatar_id => $self->session->{user}->{gravatar_id},
				name => $self->session->{user}->{name},
				login => $self->session->{user}->{login},
			},
			account => {
				screen_name => $account,
				name => $doc->{profile}->{name},
				avatar => $doc->{profile}->{profile_image_url},
			},
			message => $message,
			created => bson_time,
			status => 'Unapproved',
		} => sub {
			my ($mango, $error, $doc) = @_;
			die("DB error") if $error;
			$self->render(text => '', status => 201);
		});
	});

	$self->render_later;
}

sub update {
	my $self = shift;

	# TODO do this properly
	die("Unauthorised") if $self->session->{user}->{_birdbath}->{role} eq 'Contributor';

	my $id = $self->req->json->{id};
	my $message = $self->req->json->{message};
	my $account = $self->req->json->{account};

	$self->app->tweets->find_one({_id => bson_oid($id)} => sub {
		my ($mango, $error, $doc) = @_;
		die("DB error") if $error;
		die("Not found") if !$doc;

		if($doc->{account} ne $account) {
			# TODO load account and add to tweet update
		}

		$self->app->tweets->update({
			_id => bson_oid($id)
		},{
			'$set' => {
				message => $message,
			},
			'$push' => {
				edits => {
					edited => bson_time,
					edited_by => {
						id => $self->session->{user}->{id},
						gravatar_id => $self->session->{user}->{gravatar_id},
						name => $self->session->{user}->{name},
						login => $self->session->{user}->{login},
					},
					previous => $doc->{message},
				}
			}
		} => sub {
			my ($mango, $error, $doc) = @_;
			die("DB error") if $error;
			$self->render(status => 200, text => '');
		});
	});

	$self->render_later;
}

sub reject {
	my $self = shift;

	# TODO do this properly
	die("Unauthorised") if $self->session->{user}->{_birdbath}->{role} eq 'Contributor';

	my $message = $self->req->json->{tweet};
	$self->app->tweets->find_one({_id => bson_oid($message)} => sub {
		my ($mango, $error, $tweet) = @_;
		die("DB error") if $error;
		die("Not found") if !$tweet;

		$self->app->tweets->update({ _id => bson_oid($message) }, {
			'$set' => {
				status => 'Rejected',
				rejected => bson_time,
				rejected_by => {
					id => $self->session->{user}->{id},
					gravatar_id => $self->session->{user}->{gravatar_id},
					name => $self->session->{user}->{name},
					login => $self->session->{user}->{login},
				}
			}
		} => sub {
			my ($mango, $error, $doc) = @_;
			die("DB error: $error") if $error;

			$self->render(json => {
				status => 'Rejected',
				rejected => bson_time,
				rejected_by => {
					id => $self->session->{user}->{id},
					gravatar_id => $self->session->{user}->{gravatar_id},
					name => $self->session->{user}->{name},
					login => $self->session->{user}->{login},
				}
			}, status => 200);
		});

	});

	$self->render_later;
}

sub undo {
	my $self = shift;

	# TODO do this properly
	die("Unauthorised") if $self->session->{user}->{_birdbath}->{role} eq 'Contributor';

	my $message = $self->req->json->{tweet};
	$self->app->tweets->find_one({_id => bson_oid($message)} => sub {
		my ($mango, $error, $tweet) = @_;
		die("DB error") if $error;
		die("Not found") if !$tweet;

		$self->app->tweets->update({ _id => bson_oid($message) }, {
			'$unset' => {
				rejected => 1,
				rejected_by => 1
			},
			'$set' => {
				status => 'Unapproved',
			}
		} => sub {
			my ($mango, $error, $doc) = @_;
			die("DB error: $error") if $error;

			$self->render(json => {
				status => 'Unapproved',
				rejected => 0,
				rejected_by => {},
			}, status => 200);
		});

	});

	$self->render_later;
}


sub approve {
	my $self = shift;

	# TODO do this properly
	die("Unauthorised") if $self->session->{user}->{_birdbath}->{role} eq 'Contributor';

	my $message = $self->req->json->{tweet};
	$self->app->tweets->find_one({_id => bson_oid($message)} => sub {
		my ($mango, $error, $tweet) = @_;
		die("DB error") if $error;
		die("Not found") if !$tweet;

		$self->app->tweets->update({ _id => bson_oid($message) }, {
			'$set' => {
				status => 'Approved',
				approved => bson_time,
				approved_by => {
					id => $self->session->{user}->{id},
					gravatar_id => $self->session->{user}->{gravatar_id},
					name => $self->session->{user}->{name},
					login => $self->session->{user}->{login},
				},
				tweeted => bson_time,
			}
		} => sub {
			my ($mango, $error, $doc) = @_;
			die("DB error: $error") if $error;

			# TODO multiple accounts
			$self->app->accounts->find_one({screen_name => $tweet->{account}->{screen_name}} => sub {
				my ($mango, $error, $doc) = @_;

				die("DB error: $error") if $error;
				die("No accounts") if !$doc;

				$self->app->tweets->find_one({ _id => bson_oid($message) } => sub {
					my ($mango, $error, $tweet) = @_;
					die("DB error: $error") if $error;
					die("Tweet not found") if !$tweet;

					# Send tweet
					my $nt = Net::Twitter->new(
					      traits   => [qw/API::RESTv1_1/],
					      ssl => 1,
					      consumer_key        => $self->config->{twitter}->{consumer_key},
					      consumer_secret     => $self->config->{twitter}->{consumer_secret},
					      access_token        => $doc->{access_token},
					      access_token_secret => $doc->{access_token_secret},
					  );
					$nt->update({status => $tweet->{message}});

					$self->render(json => {
						status => 'Approved',
						approved => bson_time,
						approved_by => {
							id => $self->session->{user}->{id},
							gravatar_id => $self->session->{user}->{gravatar_id},
							name => $self->session->{user}->{name},
							login => $self->session->{user}->{login},
						},
						tweeted => bson_time,
					}, status => 200);
				});
			});		
		});

	});

	$self->render_later;
}

1;
