#!/usr/bin/perl -w

use strict;
use Getopt::Long;
use DBI;


my ($help,
    $debug,
    $version,
    $changelog,
    $dbdriver,
    $dbname,
    $dbhost,
    $dbusername,
    $dbpassword,
    $eopk,
    $tablename,
    $columnname);

$dbdriver   = 'Pg';
$dbhost     = '';
$dbusername = $ENV{'USER'};
$tablename  = 'db_update';
$columnname = 'filename';

GetOptions('help'            => \$help,
           'debug'           => \$debug,
           'version'         => \$version,
           'changelog'       => \$changelog,
           'dbdriver=s'      => \$dbdriver,
           'dbname=s'        => \$dbname,
           'dbhost=s'        => \$dbhost,
           'username=s'      => \$dbusername,
           'password=s'      => \$dbpassword,
           'tablename=s'     => \$tablename,
           'columnname=s'    => \$columnname
    );

sub usage($) {
    my ($text) = @_;

    chomp ( my $command = `basename $0` );
    print <<EOT;
  USAGE: $command [options] <update folder> dbname
    Options:
      --help            prints this page.
      --debug           enable printing of debug messages.
      --version         prints version info.
      --changelog       display ChangeLog.

      --dbdriver        Driver used for db connection (default: \'$dbdriver\')
      --dbhost          Servername  (default: use socket access to database)
      --dbsocket        Connect to postgres server via sockets
      --username        Username (default: \'$dbusername\')
      --password        Password

      --tablename       Name of the table used for version tracking. (default: \'$tablename\')
      --columnname      Name of the "name" column (default: \'$columnname\')

EOT

    print "\n$text\n" if ($text);

    exit;
}

sub version() {
    chomp ( my $command = `basename $0` );
    print "$command Version 1.0\n";
    exit;
}

sub changelog() {
    print <<EOT;
2012-01-30 Carmen Grantham <carmen\@jigsawpublications.com.au>
        * Based on the synect-db-updater.pl but this executes all files in 
        * a folder that are not in the tablename
EOT
    exit;
}

usage(undef) if ($help);
version()    if ($version);
changelog()  if ($changelog);

sub info($) {
    my ($text) = @_;

    print("$text\n");
}

sub debug($) {
    my ($text) = @_;

    info($text) if ($debug);
}


sub updateDBStatement($$) {
    my ($dbh, $statement) = @_;

    debug('executing statement: \''.$statement.'\'');
    my $result = 0;
    eval {
        $result = $dbh->do($statement)
    };
    if ($@) {
        warn "Transaction: '$statement' aborted!\n".$dbh->errstr;
    }

    return $result;
}

sub updateDB($@) {
    my ($dbh, @statements) = @_;

    my $result = 1;
    my $statement = '';

    $dbh->{RaiseError} = 1;
    $dbh->{PrintError} = 0;
    foreach $statement (@statements) {
        $result = updateDBStatement($dbh, $statement);
        debug('result: '.$result);

        last unless ($result);
    }

    if ($result) {
        eval {
            $dbh->commit();
        };
        if ($@ || !$result) {
            warn "Transaction (updateDB): '$statement' aborted\n$@";
            eval { $dbh->rollback() };
        }
    } else {
        eval { $dbh->rollback() };
    }

    $dbh->{RaiseError} = 0;
    $dbh->{PrintError} = 1;

    return $result;
}

sub getContentsOfFolder {
    my ($folder) = @_;

    if ($folder && -x $folder) {
        if (opendir(DIR, $folder)) {
            my @files = readdir DIR;
            closedir DIR;

            # exclude files called .svn or CVS
            @files = grep(!/^(\.svn|CVS)$/, @files);

            # exclude files that end in .txt
            @files = grep(!/^.*(\.txt)$/, @files);

            # only files
            @files = grep(-f "$folder/$_", @files);

            return grep(!/^\.{1,2}$/, @files);
        } else {
            info("Unable to read directory '$folder'!");
        }
    }

    return;
}

sub sortFiles(@) {
    my @files = @_;
    my $file;
    my @sortedFiles;

    # sort files to case insensitive order
    @sortedFiles = sort { "\L$a" cmp "\L$b" } @files;

    return @sortedFiles;
}

sub readFile($) {
    my ($file) = @_;

    my $text = '';
    my $line_counter = 0;
    if (open(FIN, "<$file")) {
        while (my $line = <FIN>) {
            $line_counter++;
            chomp($line);

            next if ($line =~ /^\s*--/);
            if ($line =~ /^\s*(begin|commit)\s*;/i) {
                undef($text);
                info($file.':'.$line_counter.' TEXT: \''.$line.'\'');
                last;
            }

            $text .= $line."\n";
        }

        close(FIN);
    } else {
        info('Unable to read file \''.$file.'\'');
    }

    if (!$text) {
        info('Error while reading file \''.$file.'\'');
        exit;
    }

    return $text;
}


sub notPatched($$) {
    my ($dbh, $file) = @_;
    my $sth = $dbh->prepare("SELECT * FROM ${tablename} WHERE ${columnname} = ?");
    $sth->execute($file);

    if ($sth->rows == 0) {
        return 1;
    }
    return 0;
}


sub insertPatchedFile($$) {
    my ($dbh, $file) = @_;

    return updateDB($dbh, "INSERT INTO ${tablename} (${columnname}) VALUES ('${file}')");
}


sub patchFile($$$) {
    my ($dbh, $folder, $file) = @_;

    info("patching file $file");

    my $path = $folder.'/'.$file;

    my $update = '';
    if (-f $path) {
        debug('processing file');
        $update .= readFile($path);
    }

    if ($update !~ /^\s*$/s) {
        if (updateDB($dbh, $update)) {
            insertPatchedFile($dbh, $file);
            return 1;
        }
    } else {
        info("Update '$file' does not contain any data!");
    }
    return 0;
}


sub patchDatabase($$) {
    my ($dbh, $folder) = @_;
    my @files = sortFiles(getContentsOfFolder($folder));
    if (@files) {
        my $id;
        my $updated = 0;
        foreach my $i (0..$#files) {
            my $file = $files[$i];
            if (notPatched($dbh, $file)) {
                if (patchFile($dbh, $folder, $file)) {
                    $updated = 1;
                } else {
                    $updated = -1;
                    last;
                }
            }
        }

        if ($updated == -1) {
            info('Error while patching database!');
        } elsif ($updated == 1) {
            info('Database has been patched!');
        } else {
            info('Database looks to be up-to-date!');
        }
    } else {
        info('Unable to find any updates.');
    }
}


sub main(@) {
    my ($folder, $dbname, $command) = @_;

    usage('Please specify the update folder!') if (!$folder);
    usage("Folder '$folder' does not exist!") if (!-d $folder);
    usage('Please specify the name of the database you wish to connect to!') unless ($dbname);

    $folder =~ s/\/$//;

    my $hostString = "";
    if ($dbhost !~ /^$/) {
        $hostString = ";host=$dbhost";
    }
    my $dbh = DBI->connect_cached("dbi:$dbdriver:dbname=$dbname$hostString", $dbusername, $dbpassword, {AutoCommit => 0})
        || die("Unable to connect to database ${dbname}\@${dbhost}.\n");

    die("Unable to connect to database ${dbname}\@${dbhost}.\n") unless ($dbh);

    debug("Connected to db ${dbname}\@${dbhost}: ${dbh}");

    patchDatabase($dbh, $folder);

    $dbh->disconnect();
}


main(@ARGV);

