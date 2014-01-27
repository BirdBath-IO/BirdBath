package BirdBath::Controller::Home;

use Mojo::Base 'Mojolicious::Controller';

use Mango::BSON qw/ bson_oid bson_time bson_true bson_false /;
use Net::Twitter;

sub welcome {
  my $self = shift;

  if(my $invite = $self->session('invite')) {
		$self->stash(invite => $invite);
	}

  $self->render();
}

sub logout {
	my $self = shift;
	$self->session(expires => -1);
	$self->redirect_to('/');
}

sub accounts {
	my $self = shift;

	my $cursor = $self->app->accounts->find({
		'$or' => [
			{
				'users.provider' => $self->session->{user}->{provider},
				'users.id' => $self->session->{user}->{id},
			},
			{
				'requests.provider' => $self->session->{user}->{provider},
				'requests.id' => $self->session->{user}->{id},	
			}
		]
	});
	$cursor->all(sub {
		my ($mango, $error, $docs) = @_;

		die("DB error") if $error;

		my @accounts;
		for my $doc (@$docs) {
			my $user;
			my $is_request = 1;
			for my $u (@{$doc->{users}}) {
				if($u->{provider} eq $self->session->{user}->{provider} &&
				   $u->{id} eq $self->session->{user}->{id}) {
					$user = $u;
					$is_request = 0;
					last;
				}
			}
			my $account = {
				screen_name => $doc->{screen_name},
				profile => {
					name => $doc->{profile}->{name},
					image_url => $doc->{profile}->{profile_image_url},
				},
				owner => {
					provider => $doc->{owner}->{provider},
				    id => $doc->{owner}->{id},
				    avatar => $doc->{owner}->{avatar},
				    name => $doc->{owner}->{name},
				    username => $doc->{owner}->{username},
				},
				role => $user->{role},
				request => $is_request,
			};
			if($user->{role} eq 'admin') {
				$account->{requests} = $doc->{requests};
				$account->{users} = $doc->{users};
			}
			push @accounts, $account;
		}

		$self->render(json => \@accounts);
	});

	$self->render_later;
}

sub tweets {
	my $self = shift;

	my $deleted = $self->req->url->query->param('deleted') // 0;

	my $cursor = $self->app->accounts->find({
		'users.provider' => $self->session->{user}->{provider},
		'users.id' => $self->session->{user}->{id},
	});
	$cursor->all(sub {
		my ($mango, $error, $docs) = @_;

		die("DB error") if $error;

		my @accounts = map { $_->{screen_name} } @$docs;

		my %args = ();
		if(!$deleted) {
			$args{deleted} = { '$exists' => bson_false };
		}

		my $cursor = $self->app->tweets->find({
			'account.screen_name' => {
				'$in' => \@accounts,
			},
			%args
		})->sort({created => -1});
		$cursor->limit(50)->all(sub {
			my ($mango, $error, $docs) = @_;

			die("DB error") if $error;

			for my $doc (@$docs) {
				if($doc->{edits}) {
					$doc->{last_edit} = $doc->{edits}->[-1];
				}
			}

			$self->render(json => $docs);
		});
	});

	$self->render_later;
}

sub delete {
	my $self = shift;

	my $account = $self->req->json->{account};
	my $id = $self->req->json->{tweet};

	$self->app->accounts->find_one({ screen_name_lc => lc($account) } => sub {
		my ($mango, $error, $doc) = @_;
		die("DB error") if $error;
		die("Not found") if !$doc;

		my $user;
		for my $u (@{$doc->{users}}) {
			if($u->{id} eq $self->session->{user}->{id} &&
			   $u->{provider} eq $self->session->{user}->{provider}) {
				$user = $u;
				last;
			}
		}

		my $can_delete = $user && $user->{role} =~ /^(admin|editor)$/;
		my %args = ();

		if(!$can_delete) {
			$args{'user.id'} = $self->session->{user}->{id};
			$args{'user.provider'} = $self->session->{user}->{provider};
		}

		$self->app->tweets->update({
			_id => bson_oid($id),
			%args
		},{
			'$set' => {
				'status' => 'Deleted',
				'deleted' => bson_time,
				'deleted_by' => {
					provider => $self->session->{user}->{provider},
				    id => $self->session->{user}->{id},
				    avatar => $self->session->{user}->{avatar},
				    name => $self->session->{user}->{name},
				    username => $self->session->{user}->{username},
				}
			}
		} => sub {
			my ($mango, $error, $doc) = @_;
			die("DB error") if $error;
			die("Not permitted") if !$doc->{n};
			$self->render(json => {
				'ok' => 1,
				'status' => 'Deleted',
				'deleted' => bson_time,
				'deleted_by' => {
					provider => $self->session->{user}->{provider},
				    id => $self->session->{user}->{id},
				    avatar => $self->session->{user}->{avatar},
				    name => $self->session->{user}->{name},
				    username => $self->session->{user}->{username},
				}
			}, status => 200);
		});

	});

	$self->render_later;
}

sub undelete {
	my $self = shift;

	my $account = $self->req->json->{account};
	my $id = $self->req->json->{tweet};

	$self->app->accounts->find_one({ screen_name_lc => lc($account) } => sub {
		my ($mango, $error, $doc) = @_;
		die("DB error") if $error;
		die("Not found") if !$doc;

		my $user;
		for my $u (@{$doc->{users}}) {
			if($u->{id} eq $self->session->{user}->{id} &&
			   $u->{provider} eq $self->session->{user}->{provider}) {
				$user = $u;
				last;
			}
		}

		my $can_delete = $user && $user->{role} =~ /^(admin|editor)$/;
		my %args = ();

		if(!$can_delete) {
			$args{'user.id'} = $self->session->{user}->{id};
			$args{'user.provider'} = $self->session->{user}->{provider};
		}

		$self->app->tweets->update({
			_id => bson_oid($id),
			%args
		},{
			'$set' => {
				'status' => 'Unapproved',
				'undeleted' => bson_time,
				'undeleted_by' => {
					provider => $self->session->{user}->{provider},
				    id => $self->session->{user}->{id},
				    avatar => $self->session->{user}->{avatar},
				    name => $self->session->{user}->{name},
				    username => $self->session->{user}->{username},
				}
			},
			'$unset' => {
				'deleted' => 1,
				'deleted_by' => 1,
			}
		} => sub {
			my ($mango, $error, $doc) = @_;
			die("DB error") if $error;
			die("Not permitted") if !$doc->{n};
			$self->render(json => {
				'ok' => 1,
				'status' => 'Unapproved',
				'deleted' => 0,
				'deleted_by' => {},
				'undeleted' => bson_time,
				'undeleted_by' => {
					provider => $self->session->{user}->{provider},
				    id => $self->session->{user}->{id},
				    avatar => $self->session->{user}->{avatar},
				    name => $self->session->{user}->{name},
				    username => $self->session->{user}->{username},
				}
			}, status => 200);
		});

	});

	$self->render_later;
}

sub retweet {
	my $self = shift;

	my $tweet = $self->req->json->{tweet};
	my $account = $self->req->json->{account};

	$self->app->accounts->find_one({ screen_name => $account } => sub {
		my ($mango, $error, $doc) = @_;
		die("DB error") if $error;
		die("Not found") if !$doc;

		$self->app->tweets->insert({
			user => {
				provider => $self->session->{user}->{provider},
			    id => $self->session->{user}->{id},
			    avatar => $self->session->{user}->{avatar},
			    name => $self->session->{user}->{name},
			    username => $self->session->{user}->{username},
			},
			account => {
				screen_name => $account,
				name => $doc->{profile}->{name},
				avatar => $doc->{profile}->{profile_image_url},
			},
			tweet => $tweet,
			created => bson_time,
			status => 'Unapproved',
			retweet => 1,
		} => sub {
			my ($mango, $error, $doc) = @_;
			die("DB error") if $error;
			$self->render(text => '', status => 201);
		});
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
				provider => $self->session->{user}->{provider},
			    id => $self->session->{user}->{id},
			    avatar => $self->session->{user}->{avatar},
			    name => $self->session->{user}->{name},
			    username => $self->session->{user}->{username},
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
						provider => $self->session->{user}->{provider},
					    id => $self->session->{user}->{id},
					    avatar => $self->session->{user}->{avatar},
					    name => $self->session->{user}->{name},
					    username => $self->session->{user}->{username},
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
					provider => $self->session->{user}->{provider},
				    id => $self->session->{user}->{id},
				    avatar => $self->session->{user}->{avatar},
				    name => $self->session->{user}->{name},
				    username => $self->session->{user}->{username},
				}
			}
		} => sub {
			my ($mango, $error, $doc) = @_;
			die("DB error: $error") if $error;

			$self->render(json => {
				status => 'Rejected',
				rejected => bson_time,
				rejected_by => {
					provider => $self->session->{user}->{provider},
				    id => $self->session->{user}->{id},
				    avatar => $self->session->{user}->{avatar},
				    name => $self->session->{user}->{name},
				    username => $self->session->{user}->{username},
				}
			}, status => 200);
		});

	});

	$self->render_later;
}

sub undo {
	my $self = shift;

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
					provider => $self->session->{user}->{provider},
				    id => $self->session->{user}->{id},
				    avatar => $self->session->{user}->{avatar},
				    name => $self->session->{user}->{name},
				    username => $self->session->{user}->{username},
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

					if($tweet->{retweet}) {
						print "Retweeting\n";
						$nt->retweet({id => $tweet->{tweet}->{id_str}});
					} else {
						print "Tweeting\n";
						$nt->update({status => $tweet->{message}});
					}

					$self->render(json => {
						status => 'Approved',
						approved => bson_time,
						approved_by => {
							provider => $self->session->{user}->{provider},
						    id => $self->session->{user}->{id},
						    avatar => $self->session->{user}->{avatar},
						    name => $self->session->{user}->{name},
						    username => $self->session->{user}->{username},
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
