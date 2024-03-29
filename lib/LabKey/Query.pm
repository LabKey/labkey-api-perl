#!/usr/bin/perl

=head1 NAME

LabKey::Query - For interacting with data in LabKey Server

=head1 SYNOPSIS

    use LabKey::Query;
    my $results = LabKey::Query::selectRows(
        -baseUrl => 'http://labkey.com:8080/labkey/',
        -containerPath => 'myFolder/',
        -schemaName => 'lists',
        -queryName => 'mid_tags',
    );

=head1 ABSTRACT

For interacting with data in LabKey Server

=head1 DESCRIPTION

This module is designed to simplify querying and manipulating data in LabKey Server.  It should more or less replicate the javascript APIs of the same names.

After the module is installed, if you need to login with a specific user you
will need to create a L<.netrc|https://www.labkey.org/Documentation/wiki-page.view?name=netrc>
file in the home directory of the user running the perl script.

In API versions 0.08 and later, you can specify the param '-loginAsGuest'
which will query the server without any credentials.  The server must permit
guest to that folder for this to work though.

=cut

package LabKey::Query;

use warnings;
use strict;
use JSON;
use Data::Dumper;
use FileHandle;
use File::Spec;
use File::HomeDir;
use Carp;
use LWP::UserAgent;
use HTTP::Cookies;
use HTTP::Request::Common;
use URI;


use vars qw($VERSION);

our $VERSION = "1.07";



=head1 FUNCTIONS

=head2 COMMON PARAMETERS

All of the functions in C<LabKey::Query> support the parameters below.

    LabKey::Query::selectRows(
        ...,
        # common required parameters
        -baseUrl => 'http://labkey.com:8080/labkey/',
        -containerPath => 'myFolder/',
        -schemaName => 'lists',
        -queryName => 'mid_tags',

        # common optional parameters
        -debug => 1,
        -apiKey => 'session|...',
        -loginAsGuest => 1,
        -netrcFile => 'path/to/netrc',
        -useragent => $ua,
        -timeout => 300
    );

=over

=item -baseUrl

The URL of the LabKey Server including the context path.
See also the environment variable C<LABKEY_URL>.

=item -containerPath

The container path where the request will be executed.

=item -schemaName

Name of a schema defined within the targeted container.

=item -queryName

Name of a query table associated with the chosen schema.

=item -debug (optional)

Produce verbose output

=item -apiKey (optional)

Use the apiKey value for authentication instead of using the netrc file.
See also the environment variable C<LABKEY_APIKEY>. See the
L<apikey|https://www.labkey.org/Documentation/wiki-page.view?name=apiKey>
documentation for more information.

=item -loginAsGuest (optional)

When set, don't authenticate using the apiKey or credentials found in the
netrc file.

=item -netrcFile (optional)

The location of a file to use in place of a .netrc file.  See also the
environment variable C<LABKEY_NETRC>.

=item -useragent (optional)

An instance of L<LWP::UserAgent> (if not provided, a new instance will be created)

=item -timeout (optional)

Timeout in seconds (used when creating a new L<LWP::UserAgent>)

=back

=head2 selectRows()

selectRows() can be used to query data from LabKey server

The following are the minimum required params:

    my $results = LabKey::Query::selectRows(
        -baseUrl => 'http://labkey.com:8080/labkey/',
        -containerPath => 'myFolder/',
        -schemaName => 'lists',
        -queryName => 'mid_tags',
    );

In addition to the common optional parameters, the following are also available:

    -viewName => 'view1',
    # filters to be applied to the query
    -filterArray => [
        ['file_active', 'eq', 1],
        ['species', 'neq', 'zebra']
    ],
    # query parameters to be applied to the query
    -parameters => [
        ['enddate', '2011/01/01'],
        ['totalDays', 15]
    ],
    # max number of rows returned
    -maxRows => 10,
    # sort order used for this query
    -sort => 'ColumnA,ColumnB',
    # offset used when running the query
    -offset => 100,
    # comma-delimited list of column names to include in the results.
    -columns => 'ColumnA,ColumnB',
    -containerFilterName => 'currentAndSubfolders',
    # 9.1 is the default.  See documentation of L<LABKEY.Query.ExtendedSelectRowsResults> for more detail
    -requiredVersion => 9.1

=head3 NOTE

In version 1.0 and later of the perl API, the default result format is 9.1.  This is different from the LabKey JS, which defaults to the earlier format for legacy purposes.

=cut

sub selectRows {
    my %args = @_;

    my @required = ('-queryName', '-schemaName');
    _checkRequiredParams(\%args, \@required);

    my $ctx = _getServerContext(%args);

    my $data = {
        'schemaName'      => $args{'-schemaName'},
        'query.queryName' => $args{'-queryName'},
        'apiVersion'      => $args{'-requiredVersion'} || 9.1
    };

    foreach (@{$args{-filterArray}}) {
        $$data{'query.' . @{$_}[0] . '~' . @{$_}[1]} = @{$_}[2];
    }

    foreach (@{$args{-parameters}}) {
        $$data{'query.param.' . @{$_}[0]} = @{$_}[1];
    }

    foreach ('viewName', 'offset', 'sort', 'maxRows', 'columns', 'containerFilterName') {
        if ($args{'-' . $_}) {
            $$data{'query.' . $_} = $args{'-' . $_};
        }
    }

    return _postData($ctx, _buildURL($ctx, 'query', 'getQuery.api'), $data);
}


=head2 insertRows()

insertRows() can be used to insert records into a LabKey table

The following are the minimum required params:

    my $insert = LabKey::Query::insertRows(
        -baseUrl => 'http://labkey.com:8080/labkey/',
        -containerPath => 'myFolder/',
        -schemaName => 'lists',
        -queryName => 'backup',
        -rows => [{
            "JobName" => 'jobName',
            "Status" => $status,
            "Log" => $log,
            "Date" => $date
        }],
    );

=cut

sub insertRows {
    my %args = @_;

    my @required = ('-queryName', '-schemaName', '-rows');
    _checkRequiredParams(\%args, \@required);

    my $ctx = _getServerContext(%args);

    my $data = {
        "schemaName" => $args{'-schemaName'},
        "queryName"  => $args{'-queryName'},
        "rows"       => $args{'-rows'}
    };

    return _postData($ctx, _buildURL($ctx, 'query', 'insertRows.api'), $data);
}


=head2 updateRows()

updateRows() can be used to update records in a LabKey table

The following are the minimum required params:

    my $update = LabKey::Query::updateRows(
        -baseUrl => 'http://labkey.com:8080/labkey/',
        -containerPath => 'myFolder/',
        -schemaName => 'lists',
        -queryName => 'backup',
        -rows => [{
            "JobName" => 'jobName',
            "Status" => $status,
            "Log" => $log,
            "Date" => $date
        }],
    );

=cut

sub updateRows {
    my %args = @_;

    my @required = ('-queryName', '-schemaName', '-rows');
    _checkRequiredParams(\%args, \@required);

    my $ctx = _getServerContext(%args);

    my $data = {
        "schemaName" => $args{'-schemaName'},
        "queryName"  => $args{'-queryName'},
        "rows"       => $args{'-rows'}
    };

    return _postData($ctx, _buildURL($ctx, 'query', 'updateRows.api'), $data);
}


=head2 deleteRows()

deleteRows() can be used to delete records in a LabKey table

The following are the minimum required params:

    my $update = LabKey::Query::deleteRows(
        -baseUrl => 'http://labkey.com:8080/labkey/',
        -containerPath => 'myFolder/',
        -schemaName => 'lists',
        -queryName => 'backup',
        -rows => [{
            "Key" => '12',
        }],
    );

=cut

sub deleteRows {
    my %args = @_;

    my @required = ('-queryName', '-schemaName', '-rows');
    _checkRequiredParams(\%args, \@required);

    my $ctx = _getServerContext(%args);

    my $data = {
        "schemaName" => $args{'-schemaName'},
        "queryName"  => $args{'-queryName'},
        "rows"       => $args{'-rows'}
    };

    return _postData($ctx, _buildURL($ctx, 'query', 'deleteRows.api'), $data);
}


=head2 executeSql()

executeSql() can be used to execute arbitrary SQL

The following are the minimum required params:

    my $result = LabKey::Query::executeSql(
        -baseUrl => 'http://labkey.com:8080/labkey/',
        -containerPath => 'myFolder/',
        -schemaName => 'study',
        -sql => 'select MyDataset.foo, MyDataset.bar from MyDataset',
    );

In addition to the common optional parameters, the following are also available:

    -maxRows => 10  #the max number of rows returned
    -sort => 'ColumnA,ColumnB'  #sort order used for this query
    -offset => 100  #the offset used when running the query
    -containerFilterName => 'currentAndSubfolders'

=cut

sub executeSql {
    my %args = @_;

    my @required = ('-schemaName', '-sql');
    _checkRequiredParams(\%args, \@required);

    my $ctx = _getServerContext(%args);

    my $data = {
        "schemaName" => $args{'-schemaName'},
        "sql"        => $args{'-sql'}
    };

    foreach ('offset', 'sort', 'maxRows', 'containerFilterName') {
        if ($args{'-' . $_}) {
            $$data{$_} = $args{'-' . $_};
        }
    }

    return _postData($ctx, _buildURL($ctx, 'query', 'executeSql.api'), $data);
}


# NOTE: this code adapted from Net::Netrc module.  It was changed so alternate locations could be supplied for a .netrc file
sub _readrc {

    my $host = shift || 'default';
    my $file = shift;

    #allow user to supply netrc location
    if(!$file || !-e $file){
        $file = File::Spec->catfile( File::HomeDir::home(), '.netrc' );
    }
    if ( !-e $file ) {
        $file = File::Spec->catfile( File::HomeDir::home(), '_netrc' );
    }

    my %netrc = ();
    my $fh;
    local $_;

    $netrc{default} = undef;

    # OS/2 and Win32 do not handle stat in a way compatable with this check :-(
    unless ( $^O eq 'os2'
        || $^O eq 'MSWin32'
        || $^O eq 'MacOS'
        || $^O eq 'darwin'
        || $^O =~ /^cygwin/ )
    {
        my @stat = stat($file);

        if (@stat) {
            if ( $stat[2] & 077 ) {
                carp "Bad permissions: $file";
                return;
            }
            if ( $stat[4] != $< ) {
                carp "Not owner: $file";
                return;
            }
        }
    }

    if ( $fh = FileHandle->new( $file, "r" ) ) {
        my ( $mach, $macdef, $tok, @tok ) = ( 0, 0 );

        while (<$fh>) {
            undef $macdef if /\A\n\Z/;

            if ($macdef) {
                push( @$macdef, $_ );
                next;
            }

            s/^\s*//;
            chomp;

            while ( length && s/^("((?:[^"]+|\\.)*)"|((?:[^\\\s]+|\\.)*))\s*// )
            {
                ( my $tok = $+ ) =~ s/\\(.)/$1/g;
                push( @tok, $tok );
            }

          TOKEN:
            while (@tok) {
                if ( $tok[0] eq "default" ) {
                    shift(@tok);
                    $mach = bless {};
                    $netrc{default} = [$mach];

                    next TOKEN;
                }

                last TOKEN
                  unless @tok > 1;

                $tok = shift(@tok);

                if ( $tok eq "machine" ) {
                    my $host = shift @tok;
                    $mach = { machine => $host };

                    $netrc{$host} = []
                      unless exists( $netrc{$host} );
                    push( @{ $netrc{$host} }, $mach );
                }
                elsif ( $tok =~ /^(login|password|account)$/ ) {
                    next TOKEN unless $mach;
                    my $value = shift @tok;

          # Following line added by rmerrell to remove '/' escape char in .netrc
                    $value =~ s/\/\\/\\/g;
                    $mach->{$1} = $value;
                }
                elsif ( $tok eq "macdef" ) {
                    next TOKEN unless $mach;
                    my $value = shift @tok;
                    $mach->{macdef} = {}
                      unless exists $mach->{macdef};
                    $macdef = $mach->{machdef}{$value} = [];
                }
            }
        }
        $fh->close();
    }

    my $auth = $netrc{$host}[0];

    #if no machine is specified and there is only 1 machine in netrc, we use that one
    if (!$auth && length((keys %netrc))==1){
        $auth = $netrc{(keys %netrc)[0]}[0];
    }

    warn("Unable to find entry for host: $host") unless $auth;
    warn("Missing password for host: $host") unless $auth->{password};
    warn("Missing login for host: $host") unless $auth->{login};

    return $auth;
}


sub _normalizeSlash {
    my ($containerPath) = @_;

    $containerPath =~ s/^\///;
    $containerPath =~ s/\/$//;
    $containerPath .= '/';
    return $containerPath;
}


sub _postData {
    my ($ctx, $url, $data) = @_;

    print "POST " . $url . "\n" if $$ctx{debug};
    print Dumper($data) if $$ctx{debug};

    my $json_obj = JSON->new->utf8->encode($data);

    my $req = POST $url;
    $req->content_length(length($json_obj));
    $req->content_type('application/json');
    $req->content($json_obj);
    $req->authorization_basic($$ctx{auth}{'login'}, $$ctx{auth}{'password'});

    my $response = $$ctx{userAgent}->request($req);

    # Simple error checking
    if ( $response->is_error ) {
        croak($response->status_line . '\n' . $response->decoded_content);
    }

    my $response_json = JSON->new->utf8->decode( $response->content )
      || croak("ERROR: Unable to decode JSON.\n$url\n");

    return $response_json;
}

sub _createUserAgent {
    my %args = @_;

    my $ua = LWP::UserAgent->new;
    $ua->agent("LabKey Perl API/" . $VERSION);
    $ua->cookie_jar(HTTP::Cookies->new());

    if ($args{'-timeout'}) {
        print "setting timeout to " . $args{'-timeout'} . "\n";
        $ua->timeout($args{'-timeout'});
    }
    return $ua;
}

sub _buildURL {
    my ($ctx, $controller, $action) = @_;

    return URI->new(
        _normalizeSlash($$ctx{baseUrl})
        . _normalizeSlash($controller)
        . _normalizeSlash($$ctx{containerPath})
        . $action
        . '?'
    );
}

sub _checkRequiredParams {
    my %args = %{$_[0]};
    my @required = @{$_[1]};

    foreach (@required) {
        if (!$args{$_}) {
            croak("ERROR: Missing required param: $_")
        }
    }
}

sub _fetchCSRF {
    my ($ctx) = @_;

    my $url = _buildURL($ctx, 'login', 'whoAmI.api');

    print "CRSF " . $url . "\n" if $$ctx{debug};

    my $req = GET $url;
    $req->content_type('application/json');

    if (!$$ctx{isGuest}) {
        $req->authorization_basic($$ctx{auth}{'login'}, $$ctx{auth}{'password'});
    }

    my $response = $$ctx{userAgent}->request($req);

    if ($response->is_error) {
        croak($response->status_line . '\n' . $response->decoded_content);
    }

    my $json_obj = JSON->new->utf8->decode($response->content)
        || croak("ERROR: Unable to decode JSON.\n$url\n");

    return $$json_obj{'CSRF'};
}

sub _getServerContext {
    my %args = @_;

    #allow baseUrl as environment variable
    $args{'-baseUrl'} = $args{'-baseUrl'} || $ENV{LABKEY_URL};

    my @required = ('-containerPath', '-baseUrl');
    _checkRequiredParams(\%args, \@required);

    #if no machine supplied, extract domain from baseUrl
    if (!$args{'-machine'}) {
        $args{'-machine'} = URI->new($args{'-baseUrl'})->host;
    }

    my $is_guest;
    my $lk_config;
    my $api_key = $args{-apiKey} || $ENV{LABKEY_APIKEY};
    my $netrc_file = $args{-netrcFile} || $ENV{LABKEY_NETRC};

    if ($args{'-loginAsGuest'}) {
        $is_guest = 1;
    }
    elsif ($api_key) {
        $lk_config = {
            login => 'apikey',
            password => $args{'-apiKey'}
        };
    }
    else {
        $lk_config = _readrc($args{-machine}, $netrc_file);
        $is_guest = 0;
    }

    my $ctx = {
        auth          => $lk_config,
        baseUrl       => $args{'-baseUrl'},
        containerPath => $args{'-containerPath'},
        isGuest       => $is_guest,
        userAgent     => $args{'-useragent'} || _createUserAgent(%args),
    };

    if ($args{-debug}) {
        $$ctx{debug} = 1;
    }

    my $csrfHeader = "X-LABKEY-CSRF";

    if (!$$ctx{userAgent}->default_header($csrfHeader)) {
        $$ctx{userAgent}->default_header($csrfHeader => _fetchCSRF($ctx));
    }

    return $ctx;
}

=pod

=head1 ENVIORNMENT VARIABLES

=over 4

=item *
The 'LABKEY_URL' environment variable can be used instead of supplying a '-baseUrl' param.

=item *
The 'LABKEY_NETRC' environment variable can be used to specify an alternate location of a netrc file, if not in the user's home directory.

=item *
The 'LABKEY_APIKEY' environment variable can be used to specify an apiKey to be used for authentication instead of using a netrc file.

=back

=head1 AUTHOR

LabKey C<info@labkey.com>

=head1 CONTRIBUTING

Send comments, suggestions and bug reports to:

L<https://www.labkey.org/home/developer/forum/project-start.view>


=head1 COPYRIGHT

Copyright (c) 2010 Ben Bimber
Copyright (c) 2011-2020 LabKey Corporation

=head1 LICENSE

Licensed under the Apache License, Version 2.0: http://www.apache.org/licenses/LICENSE-2.0

=head1 SEE ALSO

The LabKey client APIs are described in greater detail here:
https://www.labkey.org/Documentation/wiki-page.view?name=viewAPIs

Support questions should be directed to the LabKey forum:
https://www.labkey.org/home/Server/Forum/announcements-list.view

=cut

1;

