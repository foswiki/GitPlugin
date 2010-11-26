=pod

---+ package Foswiki::Store::Git

Wrapper around the Git commands required by Foswiki.
There is one of these object for each file stored under Git.

=cut

package Foswiki::Store::Git;

use Foswiki;
use Foswiki::Time;
use Foswiki::Sandbox;
use Foswiki::Func;

require File::Copy;
require Foswiki::Plugins::GitPlugin::GitRun;

use strict;
use Assert;

sub new {
	my( $class, $session, $web, $topic, $attachment ) = @_;
	my $this = bless( {}, $class );

	$this->{session} = $session;
	$this->{web} = $web;

	#used to record current version number
	$this->{currentRev} = undef;
	$this->{revs} = [];

	#{file} absolute path
	#{relfile} relative path to foswiki/
	#{gitfile} files path which will be added into git repository
	#{rcsFile} rcs files' path

	if( $topic ) {
        	$this->{topic} = $topic;

        	if( $attachment ) {
	        	$this->{attachment} = $attachment;
			$this->{file} = $Foswiki::cfg{PubDir}.'/'.$web.'/'.$this->{topic}.'/'.$attachment;
			$this->{relfile} = "pub".'/'.$web.'/'.$this->{topic}.'/'.$attachment;
			$this->{gitfile} = $Foswiki::cfg{Git}{root}.'/'.$this->{relfile};
			$this->{rcsFile} = $this->{file}.',v';
        	} else {
            		$this->{file} = $Foswiki::cfg{DataDir}.'/'.$web.'/'.$topic.'.txt';
			$this->{relfile} = "data".'/'.$web.'/'.$topic.'.txt';
			$this->{gitfile} = $Foswiki::cfg{Git}{root}.'/'.$this->{relfile};
			$this->{rcsFile} = $this->{file}.',v';
        	}
    	}
	return $this;
}

=pod

---++ ObjectMethod finish
Complete processing after the client's HTTP request has been responded
to.
   1 breaking circular references to allow garbage collection in persistent
     environments

=cut

sub finish {
	my $this = shift;
	undef $this->{file};
	undef $this->{relfile};
	undef $this->{gitfile};
	undef $this->{rcsFile};
	undef $this->{web};
	undef $this->{topic};
	undef $this->{attachment};
	undef $this->{session};

	undef $this->{currentRev};
	undef $this->{revs};

	return;
}

=pod

---++ ObjectMethod storedDataExists() -> $boolean
Establishes if there is stored data associated with this handler.

=cut

sub storedDataExists {
    my $this = shift;
    return -e $this->{file};
}


#######################     Topic     #######################

=pod

---++ sub _readFile

=cut
###Copy from RCS
sub _readFile {
    my( $this, $name ) = @_;
    my $data;
    my $IN_FILE;
    if( open( $IN_FILE, '<', $name )) {
        binmode( $IN_FILE );
        local $/ = undef;
        $data = <$IN_FILE>;
        close( $IN_FILE );
    }
    $data ||= '';
    return $data;
}



=pod

---++ ObjectMethod getTopicNames() -> @topics

Get list of all topics in a web
   * =$web= - Web name, required, e.g. ='Sandbox'=
Return a topic list, e.g. =( 'WebChanges',  'WebHome', 'WebIndex', 'WebNotify' )=

=cut
###Copy from RCS
sub getTopicNames {
    my $this = shift;

    opendir DIR, $Foswiki::cfg{DataDir}.'/'.$this->{web};
    # the name filter is used to ensure we don't return filenames
    # that contain illegal characters as topic names.
    my @topicList =
      sort
        map { Foswiki::Sandbox::untaintUnchecked( $_ ) }
          grep { !/$Foswiki::cfg{NameFilter}/ && s/\.txt$// }
            readdir( DIR );
    closedir( DIR );
    return @topicList;
}


=pod

---++ ObjectMethod getLatestRevision() -> $text
Get the text of the most recent revision

=cut
###Copy from RCS
sub getLatestRevision {
    my $this = shift;
    return _readFile( $this, $this->{file} );
}



sub numRevisions {
    my( $this ) = @_;
	return _localNumRevisions( @_ ) if ( _isLocalWeb( $this->{web} ) );
	return $this->_getVersionArray();
}


sub _localNumRevisions{
    my( $this ) = @_;

    unless( -e $this->{rcsFile}) {
        return 1 if( -e $this->{file} );
        return 0;
    }

    my ($rcsOutput, $exit) =
      $Foswiki::sandbox->sysCommand
        ( $Foswiki::cfg{RCS}{histCmd},
          FILENAME => $this->{rcsFile} );
    if( $exit ) {
        throw Error::Simple( 'RCS: '.$Foswiki::cfg{RCS}{histCmd}.
                               ' of '.$this->hidePath($this->{rcsFile}).
                                 ' failed: '.$rcsOutput );
    }

    if( $rcsOutput =~ /head:\s+\d+\.(\d+)\n/ ) {
        return $1;
    }
    if( $rcsOutput =~ /total revisions: (\d+)\n/ ) {
        return $1;
    }
    return 1;
}


=pod

---++ _getVersionArray()
Get all versions' information and the current version

=cut
sub _getVersionArray {
    my ( $this ) = @_;

	#have get this information just before
	return $this->{currentRev} if defined $this->{currentRev};

	#judge whether the web is not to use Git.
	return _localGetVersionArray( @_ ) if ( _isLocalWeb( $this->{web} ) );

	#$Foswiki::cfg{Git}{numRevisions} = "$Foswiki::cfg{Git}{BinDir}/git log --follow %FILENAME|F%"
	my ( $gitOut, $exit ) = Foswiki::Plugins::GitPlugin::GitRun::render( $Foswiki::cfg{Git}{numRevisions}, FILENAME => $this->{relfile} );

	if( !$exit && $gitOut )
	{
		#Get the Max version number
		if( $gitOut =~ m/(.*?)TW_Version:([0-9]*).*/s)
		{
			$this->{currentRev} = $2;
		}

		my $eachCommit;
		my @commitsArray = split /commit/, $gitOut;
		foreach $eachCommit (@commitsArray)
		{
			if( $eachCommit =~ m/\s(.*?)\s(.*?)TW_Version:([0-9]*)\s(.*?)TW_Author:([0-9a-zA-Z_]*)\s(.*?)TW_Path:(.*?)\s(.*?)TW_Comment:(.*?)\s(.*?)TW_Date:(.*?)\s/s )
			{
				unless( defined ${$this->{revs}}[$3 - 1] )
				{
					${$this->{revs}}[$3 - 1] = {"SHA1"=>$1, "Author"=>$5, "Path"=>$7, "Comment"=>$9, "Date"=>$11};
				}
			}
		}
		return $this->{currentRev};
	}
	return;
}

=pod

---++ _localGetVersionArray() 
Get all versions' information and local current version. This is not for Git using but some else codes, for example, RCS.

=cut

sub _localGetVersionArray{
        my ( $this ) = @_;
        return;
}

=pod

---++ getRevision()
Get the $version raw text

=cut

sub getRevision {
	my( $this, $version ) = @_;

	#judge whether the web is not to use Git.
	return _localGetRevision( @_ ) if ( _isLocalWeb( $this->{web} ) );

	if ( !@{$this->{revs}} ) 
	{
		$this->_getVersionArray();
	}

	#first, get the SHA-1 value relative to the version
	my $sha1;
	my $path;	#because after file rename, we lost the old name, we stored it in comment

	#we have stored all version information in _getVersionArray()
	$sha1 = ${$this->{revs}}[$version - 1]->{SHA1};
	$path = ${$this->{revs}}[$version - 1]->{Path};

	#second, get raw text of the topic
	my $text;
	my ( $gitOut, $exit ) = Foswiki::Plugins::GitPlugin::GitRun::render(
					$Foswiki::cfg{Git}{coCmd},
					SHA1 => $sha1,
					FILENAME => $path );

	if( !$exit )
	{
		$text= $gitOut;
	}

	return $text;
}


=pod

---++ _localGetRevision()
Get the $version raw tesxt. This is not for Git using but for some else codes, for example, RCS.

=cut
sub _localGetRevision{
        my( $this, $version ) = @_;

	unless( $version && -e $this->{rcsFile} ) {
        return _readFile( $this, $this->{file} );
    }

    my $tmpfile = '';
    my $tmpRevFile = '';
    my $coCmd = $Foswiki::cfg{RCS}{coCmd};
    my $file = $this->{file};
    if( $Foswiki::cfg{RCS}{coMustCopy} ) {
        # SMELL: is this really necessary? What evidence is there?
        # Need to take temporary copy of topic, check it out to file,
        # then read that
        # Need to put RCS into binary mode to avoid extra \r appearing and
        # read from binmode file rather than stdout to avoid early file
        # read termination
        $tmpfile = mkTmpFilename( $this );
        $tmpRevFile = $tmpfile.',v';
        copy( $this->{rcsFile}, $tmpRevFile );
        my ($tmp, $status) = $Foswiki::sandbox->sysCommand(
            $Foswiki::cfg{RCS}{tmpBinaryCmd},
            FILENAME => $tmpRevFile );
        $file = $tmpfile;
        $coCmd =~ s/-p%REVISION/-r%REVISION/;
    }
    my ($text, $status) = $Foswiki::sandbox->sysCommand(
        $coCmd,
        REVISION => '1.'.$version,
        FILENAME => $file );

    if( $tmpfile ) {
        $text = _readFile( $this, $tmpfile );
        # SMELL: Is untainting really necessary here?
        unlink Foswiki::Sandbox::untaintUnchecked( $tmpfile );
        unlink Foswiki::Sandbox::untaintUnchecked( $tmpRevFile );
    }
	
    return $text;
}


=pod
---++ getRevisionInfo($this, $version)
get revision information from special $version

=cut

sub getRevisionInfo {
	my( $this, $version ) = @_;

	#judge whether the web is not to use Git.
	return _localGetRevisionInfo( @_ ) if ( _isLocalWeb( $this->{web} ) );

	my $versionInfo = $this->_getGitRev( $version );

	#missing comments and date information
	return($version, $versionInfo->{Date}, $versionInfo->{Author}, $versionInfo->{Comment});
}


=pod

---++ _localGetRevisionInfo($version) -> ($rev, $date, $user, $comment)
This is not for Git using but for some else codes, for example, RCS.

=cut
sub _localGetRevisionInfo{
	my ( $this, $version ) = @_;

	if( -e $this->{rcsFile} ) {
        if( !$version || $version > $this->numRevisions()) {
            $version = $this->numRevisions();
        }
        my( $rcsOut, $exit ) = $Foswiki::sandbox->sysCommand
          ( $Foswiki::cfg{RCS}{infoCmd},
            REVISION => '1.'.$version,
            FILENAME => $this->{rcsFile} );
        if( ! $exit ) {
            if( $rcsOut =~ /^.*?date: ([^;]+);  author: ([^;]*);[^\n]*\n([^\n]*)\n/s ) {
                my $user = $2;
                my $comment = $3;
                require Foswiki::Time;
                my $date = Foswiki::Time::parseTime( $1 );
                my $rev = $version;
                if( $rcsOut =~ /revision 1.([0-9]*)/ ) {
                    $rev = $1;
                    return( $rev, $date, $user, $comment );
                }
            }
        }
    }

	my $fileDate = $this->getTimestamp();
	return ( 1, $fileDate, $this->{session}->{users}->getCanonicalUserID($Foswiki::cfg{DefaultUserLogin}),
             'Default revision information' );
}


=pod

---++ _getGitRev()
Get the $version  information

=cut

sub _getGitRev {
    my ($this,$version) = @_;
    return if $version < 1;

    $this->_getVersionArray();
    return ${$this->{revs}}[$version - 1];
}


=pod
---++ revisionDiff($this, $rev1, $rev2, $contextLines)

=cut

sub revisionDiff {
    my( $this, $rev1, $rev2, $contextLines ) = @_;
    my( $gitOut, $exit );

    #judge whether the web is not to use Git.
    return _localRevisionDiff( @_ ) if ( _isLocalWeb( $this->{web} ) );

    if ( $rev1 eq '1' && $rev2 eq '1' )
	{
        	my $text = $this->getRevision(1);
	        $gitOut = "1a1\n";
	        foreach( split( /\r?\n/, $text ) )
		{
        		$gitOut = "$gitOut> $_\n";
        	}
		return parseRevisionDiff( $gitOut, 0 );
	}
	else
	{
		$this->_getVersionArray();

        $contextLines = 3 unless defined($contextLines);
	#$Foswiki::cfg{Git}{diffCmd} = "$Foswiki::cfg{Git}{BinDir}/git diff -w %REVISION1% %REVISION2% --unified=%CONTEXT|N% %FILENAME|F%";
	#REVISION|N, because 'N'limit to 30 characters, so SHA1 is invalid 
	( $gitOut, $exit ) = Foswiki::Plugins::GitPlugin::GitRun::render(
			            $Foswiki::cfg{Git}{diffCmd},
			            REVISION1 => ${$this->{revs}}[$rev1 - 1]->{SHA1},
			            REVISION2 => ${$this->{revs}}[$rev2 - 1]->{SHA1},
			            FILENAME1 => ${$this->{revs}}[$rev1 - 1]->{Path},
				    FILENAME2 => ${$this->{revs}}[$rev2 - 1]->{Path},
			            CONTEXT => $contextLines );
    	return parseRevisionDiff( $gitOut, 1 );
	}
}


=pod

---++ _localRevisionDiff( $rev1, $rev2, $contextLines )
This is not for Git using but some else codes, for example, RCS.

=cut
sub _localRevisionDiff{
        my( $this, $rev1, $rev2, $contextLines ) = @_;
    my $tmp = '';
    my $exit;
    if ( $rev1 eq '1' && $rev2 eq '1' ) {
        my $text = $this->getRevision(1);
        $tmp = "1a1\n";
        foreach( split( /\r?\n/, $text ) ) {
            $tmp = "$tmp> $_\n";
        }
    } else {
        $contextLines = 3 unless defined($contextLines);
        ( $tmp, $exit ) = $Foswiki::sandbox->sysCommand(
            $Foswiki::cfg{RCS}{diffCmd},
            REVISION1 => '1.'.$rev1,
            REVISION2 => '1.'.$rev2,
            FILENAME => $this->{rcsFile},
            CONTEXT => $contextLines );
        # comment out because we get a non-zero status for a good result!
        #if( $exit ) {
        #    throw Error::Simple( 'RCS: '.$Foswiki::cfg{RCS}{diffCmd}.
        #                           ' failed: '.$! );
        #}
    }

    return _localParseRevisionDiff( $tmp );
}


=pod

---++ StaticMethod parseRevisionDiff( $text ) -> \@diffArray

| Description: | parse the text into an array of diff cells |
| #Description: | unlike Algorithm::Diff I concatinate lines of the same diffType that are sqential (this might be something that should be left up to the renderer) |
| Parameter: =$text= | currently unified or rcsdiff format |
| Return: =\@diffArray= | reference to an array of [ diffType, $right, $left ] |
| TODO: | move into RcsFile and add indirection in Store |

=cut

sub _localParseRevisionDiff {
    my( $text ) = @_;

    my ( $diffFormat ) = 'normal'; #or rcs, unified...
    my ( @diffArray ) = ();

    $diffFormat = 'unified' if ( $text =~ /^---/s );

    $text =~ s/\r//go;  # cut CR

    my $lineNumber=1;
    if ( $diffFormat eq 'unified' ) {
        foreach( split( /\r?\n/, $text ) ) {
            if ( $lineNumber > 2 ) {   #skip the first 2 lines (filenames)
                if ( /@@ [-+]([0-9]+)([,0-9]+)? [-+]([0-9]+)(,[0-9]+)? @@/ ) {
                        #line number
                    push @diffArray, ['l', $1, $3];
                } elsif( /^\-(.*)$/ ) {
                    push @diffArray, ['-', $1, ''];
                } elsif( /^\+(.*)$/ ) {
                    push @diffArray, ['+', '', $1];
                } else {
                    s/^ (.*)$/$1/go;
                    push @diffArray, ['u', $_, $_];
                }
            }
            $lineNumber++;
        }
    } else {
        #'normal' rcsdiff output
        foreach( split( /\r?\n/, $text ) ) {
            if ( /^([0-9]+)[0-9\,]*([acd])([0-9]+)/ ) {
                #line number
                push @diffArray, ['l', $1, $3];
            } elsif( /^< (.*)$/ ) {
                    push @diffArray, ['-', $1, ''];
            } elsif( /^> (.*)$/ ) {
                    push @diffArray, ['+', '', $1];
            } else {
                #push @diffArray, ['u', '', ''];
            }
        }
    }
    return \@diffArray;
}


=pod

---++ StaticMethod parseRevisionDiff( $text ) -> \@diffArray

| Description: | parse the text into an array of diff cells |
| #Description: | unlike Algorithm::Diff I concatinate lines of the same diffType that are sqential (this might be something that should be left up to the renderer) |
| Parameter: =$text= | currently unified or rcsdiff format |
| Return: =\@diffArray= | reference to an array of [ diffType, $right, $left ] |

=cut

sub parseRevisionDiff {
    my( $text, $isDiff ) = @_;

    my ( @diffArray ) = ();

#format of $text
#index 5a16afe..2a73483 100755
#--- a/data/Sandbox/TestDiff.txt
#+++ b/data/Sandbox/TestDiff.txt
#@@ -1,13 +1,13 @@
#...

    $text =~ s/\r//go;  # cut CR

    my $lineNumber=1;
	
	if( $isDiff )
	{
		foreach( split( /\r?\n/, $text ) ) {
			if ( $lineNumber > 4 ) {   #skip the first 4 lines
				if ( /@@ [-+]([0-9]+)([,0-9]+)? [-+]([0-9]+)(,[0-9]+)? @@/ ) {
					push @diffArray, ['l', $1, $3];
				} elsif( /^\-(.*)$/ ) {
					push @diffArray, ['-', $1, ''];
				} elsif( /^\+(.*)$/ ) {
					push @diffArray, ['+', '', $1];
				} elsif( s/^ (.*)$/$1/go ) {
					push @diffArray, ['u', $_, $_];
				}
			}
			$lineNumber++;
		}
	}
	else
	{
		foreach( split( /\r?\n/, $text ) ) {
			if ( /^([0-9]+)[0-9\,]*([acd])([0-9]+)/ ) {
				#line number
				push @diffArray, ['l', $1, $3];
			} elsif( /^< (.*)$/ ) {
				push @diffArray, ['-', $1, ''];
			} elsif( /^> (.*)$/ ) {
				push @diffArray, ['+', '', $1];
			} else {
				#push @diffArray, ['u', '', ''];
			}
        }
	}
    return \@diffArray;
}



=pod

---++ ObjectMethod getLatestRevisionTime() -> $text

Get the time of the most recent revision

=cut
###Copy from RCS
sub getLatestRevisionTime {
    my @e = stat( shift->{file} );
    return $e[9] || 0;
}


=pod

---++ ObjectMethod getTimestamp() -> $integer

Get the timestamp of the file
Returns 0 if no file, otherwise epoch seconds

=cut
###Copy from RCS
sub getTimestamp {
    my( $this ) = @_;
    my $date = 0;
    if( -e $this->{file} ) {
        # SMELL: Why big number if fail?
        $date = (stat $this->{file})[9] || 600000000;
    }
    return $date;
}



sub addRevisionFromText {
    my( $this, $text, $comment, $user, $date ) = @_;

    return _localAddRevisionFromText( @_ ) if ( _isLocalWeb( $this->{web} ) );
	
    #if it's a new topic, touch it.
    $this->init();
	
    if( !$this->{version} )
    {
	my $tmp = $this->numRevisions();
	$tmp = 0 unless defined $tmp;
	$this->{version} = $tmp + 1;
    }
 
    $this->_saveFile( $this->{file}, $text );
    $this->_ci( $comment, $user, $date );
}


sub _localAddRevisionFromText{
    my( $this, $text, $comment, $user, $date ) = @_;
    $this->_localInit();

    unless( -e $this->{rcsFile} ) {
        _lock( $this );
        _localci( $this, $comment, $user, $date );
    }
    _saveFile( $this, $this->{file}, $text );
    _lock( $this );
    _localci( $this, $comment, $user, $date );
}


=pod
---++ replaceRevision
commit a topic with the same version number of the former, simulate replace operation
=cut

sub replaceRevision {
    my( $this, $text, $comment, $user, $date ) = @_;

    return _localReplaceRevision( @_ ) if ( _isLocalWeb( $this->{web} ) );

    $this->{version} = $this->numRevisions();

    return addRevisionFromText( @_ );
}

sub _localReplaceRevision {
    my( $this, $text, $comment, $user, $date ) = @_;

    my $rev = $this->_localNumRevisions();

    $comment ||= 'none';

    # update repository with same userName and date
    if( $rev == 1 ) {
        # initial revision, so delete repository file and start again
        unlink $this->{rcsFile};
    } else {
        _deleteRevision( $this, $rev );
    }

    _saveFile( $this, $this->{file}, $text );
    require Foswiki::Time;
	$date = Foswiki::Time::formatTime( $date , '$rcs', 'gmtime');

    _lock( $this );
    my ($rcsOut, $exit) =
      $Foswiki::sandbox->sysCommand(
          $Foswiki::cfg{RCS}{ciDateCmd},
          DATE => $date,
          USERNAME => $user,
          FILENAME => $this->{file},
          COMMENT => $comment );
    if( $exit ) {
        $rcsOut = $Foswiki::cfg{RCS}{ciDateCmd}."\n".$rcsOut;
        return $rcsOut;
    }
    chmod( $Foswiki::cfg{RCS}{filePermission}, $this->{file} );
}


=pod
---++ deleteRevision
delete version can't be supported by Git, and we can't find a method to realize it

=cut

sub deleteRevision {
	#???
	my( $this ) = @_;
	return _localDeleteRevision( @_ ) if ( _isLocalWeb( $this->{web} ) );
	return undef;
}

sub _localDeleteRevision {
    my( $this ) = @_;
    my $rev = $this->numRevisions();
    return undef if( $rev <= 1 );
    return _deleteRevision( $this, $rev );
}

sub _deleteRevision {
    my( $this, $rev ) = @_;

    # delete latest revision (unlock (may not be needed), delete revision)
    my ($rcsOut, $exit) =
      $Foswiki::sandbox->sysCommand(
          $Foswiki::cfg{RCS}{unlockCmd},
          FILENAME => $this->{file} );

    chmod( $Foswiki::cfg{RCS}{filePermission}, $this->{file} );

    ($rcsOut, $exit) = $Foswiki::sandbox->sysCommand(
        $Foswiki::cfg{RCS}{delRevCmd},
        REVISION => '1.'.$rev,
        FILENAME => $this->{file} );

    if( $exit ) {
        throw Error::Simple( $Foswiki::cfg{RCS}{delRevCmd}.
                               ' of '.$this->hidePath($this->{file}).
                                 ' failed: '.$rcsOut );
    }

    # Update the checkout
    $rev--;
    ($rcsOut, $exit) = $Foswiki::sandbox->sysCommand(
        $Foswiki::cfg{RCS}{coCmd},
        REVISION => '1.'.$rev,
        FILENAME => $this->{file} );

    if( $exit ) {
        throw Error::Simple( $Foswiki::cfg{RCS}{coCmd}.
                               ' of '.$this->hidePath($this->{file}).
                                 ' failed: '.$rcsOut );
    }
    _saveFile( $this, $this->{file}, $rcsOut );
}


#??? no Unit Test
sub getRevisionAtTime {
    my( $this, $date ) = @_;

	return _localGetRevisionAtTime( @_ ) if ( _isLocalWeb( $this->{web} ) );

	$this->numRevisions();

	my $revIndex = 0;
	
	#@{$this->{revs}} date order is decrease
	foreach (@{$this->{revs}})
	{
		if( $_->{Date} < $date )
		{
			last;
		}
		else
		{
			++$revIndex;
		}
	}

    return ${$this->{revs}}[$revIndex]->{Version};
}


sub _localGetRevisionAtTime{
    my( $this, $date ) = @_;

    if ( !-e $this->{rcsFile} ) {
        return undef;
    }
    require Foswiki::Time;
	$date = Foswiki::Time::formatTime( $date , '$rcs', 'gmtime');
    my ($rcsOutput, $exit) = $Foswiki::sandbox->sysCommand(
        $Foswiki::cfg{RCS}{rlogDateCmd},
        DATE => $date,
        FILENAME => $this->{file} );

    if ( $rcsOutput =~ m/revision \d+\.(\d+)/ ) {
        return $1;
    }
    return 1;
}

=pod

---++ ObjectMethod restoreLatestRevision($wikiname)

Restore the plaintext file from the revision at the head.
SMELL: This shortcuts the deleteRevision - restoreLatestRevision
SMELL: combo by going back to the last-1 revision.

=cut
sub restoreLatestRevision {
    my( $this, $user ) = @_;

    return _localRestoreLatestRevision( @_ ) if ( _isLocalWeb( $this->{web} ) );

    my $rev = $this->numRevisions();
    if ( $rev > 1 ) {
		my $text = $this->getRevision( $rev - 1 );
		$this->_saveFile( $this->{file}, $text );
    }
}


=pod

---++ ObjectMethod _localRestoreLatestRevision( $user )

Restore the plaintext file from the revision at the head. This is not for Git using.

=cut

sub _localRestoreLatestRevision {
    my( $this, $user ) = @_;

    my $rev = $this->_localNumRevisions();
    my $text = $this->_localGetRevision( $rev );

    # If there is no ,v, create it
    unless( -e $this->{rcsFile} ) {
        $this->_localAddRevisionFromText( $text, "restored", $user, time() );
    } else {
        _saveFile( $this, $this->{file}, $text );
    }

    return;
}

=pod
---++ saveFile
save file on disk and add to repository index, but not commit it to repository
=cut 

sub _saveFile {
    my( $this, $name, $text ) = @_;
    _mkPathTo( $name );
    open( FILE, '>'.$name ) ||
      throw Error::Simple( 'HG: failed to create .file '.$name.': '.$! );
    binmode( FILE ) ||
      throw Error::Simple( 'HG: failed to binmode '.$name.': '.$! );
    print FILE $text;
    close( FILE) ||
      throw Error::Simple( 'HG: failed to close file '.$name.': '.$! );

	#judge whether the web is not to use Git.
	return _localSaveFile( @_ ) if ( _isLocalWeb( $this->{web} ) );
	
	my ( $gitOutput, $exit ) = Foswiki::Plugins::GitPlugin::GitRun::render(
		    			$Foswiki::cfg{Git}{initCmd},
					FILENAME => $this->{relfile} );
	if( $exit ) {
	    throw Error::Simple( $Foswiki::cfg{Git}{initCmd}.
		    ' of '.$this->_hidePath($this->{file}).
		    ' failed: '.$gitOutput );
	}

    return undef;
}


=pod

---++ localSaveFile( $name, $text )
add File to repository. This is not for Git using but some else codes, for example, RCS.

=cut
sub _localSaveFile{
        my( $this, $name, $text ) = @_;
        return;
}


=pod

---++ ObjectMethod moveTopic( $newWeb, $newTopic )
Move/rename a topic.

=cut

sub moveTopic {
    my( $this, $newWeb, $newTopic ) = @_;

    my $oldWeb = $this->{web};
    my $oldTopic = $this->{topic};

    # Move data file
    my $new = new Foswiki::Store::Git( $this->{session},
					$newWeb, $newTopic, '' );

	#judeg from web and to web, all will use Git, or all will not , or one will and one will not.
	if ( _isLocalWeb( $this->{web} ) and ( _isLocalWeb( $new->{web} ) or $newWeb eq $Foswiki::cfg{TrashWebName} ) )
	{
		_localMoveFile( $this, $this->{file}, $new->{file} );

		# Move history
		_mkPathTo( $new->{rcsFile});
		if( -e $this->{rcsFile} ) {
		    _localMoveFile( $this, $this->{rcsFile}, $new->{rcsFile} );
		}

	# Move attachments
	my $from = $Foswiki::cfg{PubDir}.'/'.$this->{web}.'/'.$this->{topic};
	if( -e $from ) {
		my $to = $Foswiki::cfg{PubDir}.'/'.$newWeb.'/'.$newTopic;
		_localMoveFile( $this, $from, $to );
	}
	}
	elsif ( !_isLocalWeb( $this->{web} ) and !_isLocalWeb( $new->{web} ) )
	{
	_moveFile( $this->{gitfile}, $new->{gitfile} );

	# Move attachments
	my $from = $Foswiki::cfg{Git}{root}.'/'.'pub'.'/'.$this->{web}.'/'.$this->{topic};
	if( -e $from ) {
        my $to = $Foswiki::cfg{Git}{root}.'/'.'pub'.'/'.$newWeb.'/'.$newTopic;
        _moveFile( $from, $to );
	}
	}
	else
	{
		my $info = "could not move topic $this->{topic} from !$this->{web} to !$newWeb, because one is out-sync web and the other is not.";
		throw Error::Simple( "permission deney:".$info );
	}
}


=pod

if file is in data/ $from and $to are relative path.
if file is in pub/ $from and $to are absolute path.

=cut


sub _moveFile {
    my( $from, $to ) = @_;
    _mkPathTo( $to );

    my ($gitOut, $exit) = Foswiki::Plugins::GitPlugin::GitRun::render(
					$Foswiki::cfg{Git}{moveCmd},
					SOURCE => $from,
					DEST => $to );

    if( $exit ) {
        throw Error::Simple( 'HG: move '.$from.' to '.$to.' failed: '.$! );
    }

	my ( $cmd, $gitOutput );
		
	my $gitComment = "TW_Rename: $from -> $to";
	
	$cmd = $Foswiki::cfg{Git}{mvciCmd};

	#it must commit the $from and $to at the same time, otherwise Git will lost the history when git log --follow
	( $gitOutput, $exit ) = Foswiki::Plugins::GitPlugin::GitRun::render(
					$Foswiki::cfg{Git}{mvciCmd},
					FILENAME1 => $from,
					FILENAME2 => $to,
					COMMENT => $gitComment );

    $gitOutput ||= '';

    if( $exit ) {
        throw Error::Simple($cmd.' failed: '.$exit.' '.$gitOutput );
    }

    _rmFile($from);
}


sub _rmFile{
	my $from = shift;
	my $absFrom = $from;

        if( $absFrom =~ m#^data/(.*)$# )
	{
        	$absFrom = $Foswiki::cfg{DataDir} . "/$1";
        }
	elsif( $absFrom =~ m#^$Foswiki::cfg{PubDir}# )
	{
        }
	else
	{
        	return;
        }

	if( open(my $IN,'>',"$absFrom") ){
		print $IN 'temp for remove';
		close($IN);
	}else{
		return;
	}

	my $gitComment = "TW_Version:0";
	my ( $gitOutput, $exit ) = Foswiki::Plugins::GitPlugin::GitRun::render(
                                        $Foswiki::cfg{Git}{initCmd},
                                        FILENAME => $from );
	( $gitOutput, $exit ) = Foswiki::Plugins::GitPlugin::GitRun::render(
                                        $Foswiki::cfg{Git}{ciCmd},
                                        FILENAME => $from,
                                        COMMENT => $gitComment );
	( $gitOutput, $exit ) = Foswiki::Plugins::GitPlugin::GitRun::render(
                                        $Foswiki::cfg{Git}{removeCmd},
                                        FILENAME => $from,
                                        COMMENT => $gitComment );
	( $gitOutput, $exit ) = Foswiki::Plugins::GitPlugin::GitRun::render(
                                        $Foswiki::cfg{Git}{ciCmd},
                                        FILENAME => $from,
                                        COMMENT => $gitComment );
}


=pod

---++ _localMoveFile( $this, $from, $to )
$from and $to must be absolutely path.
This is not for Git using but some else codes, for example, RCS.

=cut
sub _localMoveFile{
        my( $this, $from, $to ) = @_;

        my $toWeb = $1 if( ( $to =~ m#^$Foswiki::cfg{PubDir}/(.*)# ) or ( $to =~ m#^$Foswiki::cfg{DataDir}/(.*)# ) );
        $toWeb = $1 if ( $toWeb =~ m#^(.*?)/# );

	#If the web, which will not use Git, it will be deleted at now. you can replace codes here.
        if ( $toWeb eq $Foswiki::cfg{TrashWebName} )
        {
		my $localTrash = $Foswiki::cfg{DataDir}.'/'.$Foswiki::cfg{Git}{LocalTrashWebName};
		_localCreateTrash( $this ) unless ( -e $localTrash);
		$to =~ s#^($Foswiki::cfg{PubDir}/)$Foswiki::cfg{TrashWebName}#$1$Foswiki::cfg{Git}{LocalTrashWebName}#;
		$to =~ s#^($Foswiki::cfg{DataDir}/)$Foswiki::cfg{TrashWebName}#$1$Foswiki::cfg{Git}{LocalTrashWebName}#;
		_mkPathTo( $to );
	        unless( File::Copy::move( $from, $to ) ) {
        		throw Error::Simple( 'localWeb: move '.$from.' to '.$to.' failed: '.$! );
        	}
	}
	else
	{
                _mkPathTo( $to );
                unless( File::Copy::move( $from, $to ) ) {
                        throw Error::Simple( 'localWeb: move '.$from.' to '.$to.' failed: '.$! );
                }
        }

        return;
}


=pod

---++ ObjectMethod copyTopic( $newWeb, $newTopic )
Copy a topic.

=cut

sub copyTopic {
    my( $this, $newWeb, $newTopic ) = @_;

    my $oldWeb = $this->{web};
    my $oldTopic = $this->{topic};
	
    my $new = new Foswiki::Store::Git( $this->{session},
                                         $newWeb, $newTopic, '' );

    #Judge whether the to web will use Git.
    if ( _isLocalWeb( $new->{web} ) )
    {
	_localCopyFile( $this->{file}, $new->{file} );
        if( -e $this->{rcsFile} ) {
            _localCopyFile( $this->{rcsFile}, $new->{rcsFile} );
        }

    	if( opendir(my $DIR, $Foswiki::cfg{PubDir}.'/'.$this->{web}.'/'.$this->{topic} ))
	{
        	for my $att ( grep { !/^\./ } readdir $DIR )
		{
	            	$att = Foswiki::Sandbox::untaintUnchecked( $att );
        	    	my $oldAtt = new Foswiki::Store::Git(
			$this->{session}, $this->{web}, $this->{topic}, $att );
			$oldAtt->copyAttachment( $newWeb, $newTopic );
        	}
        	closedir $DIR;
    	}
    }
    else
    {
	#assign the pub/{$newWeb} access right
        my $path = $Foswiki::cfg{Git}{root}.'/'.'pub'.'/'.$newWeb.'/';
        File::Path::mkpath($path, 0, $path);
        chmod(0775, $path);

	_copyFile( $this, $this->{file}, $new->{gitfile} );
	if( opendir(DIR, $Foswiki::cfg{Git}{root}.'/'.'pub'.'/'.$this->{web}.'/'.$this->{topic} ))
	{
		for my $att ( grep { !/^\./ } readdir DIR )
		{
			$att = Foswiki::Sandbox::untaintUnchecked( $att );
			my $oldAtt = new Foswiki::Store::Git(
				$this->{session}, $this->{web}, $this->{topic}, $att );
			$oldAtt->copyAttachment( $newWeb, $newTopic );
		}
		closedir DIR;
	}
	my $FoswikiPath = $Foswiki::cfg{DataDir};
        $FoswikiPath =~ s/\/[^\/]*$//;
        my $GitPath = $Foswiki::cfg{Git}{root};
        $GitPath =~ s/\/$//;
	#make soft link if need
	if ( $FoswikiPath ne $GitPath )
        {
                _mkLink( $new->{web}, 'Data' );
		_mkLink( $new->{web}, 'Pub' );
        }

    }
}

sub _copyFile {
	my( $this, $from, $to ) = @_;

	_mkPathTo( $to );

	unless( File::Copy::copy( $from, $to ) ) {
			throw Error::Simple( 'RCS: copy '.$from.' to '.$to.' failed: '.$! );
		}

	my ($gitOut, $exit) =
		Foswiki::Plugins::GitPlugin::GitRun::render(
			$Foswiki::cfg{Git}{initCmd},
			FILENAME => $to );
	
	if( $exit ) {
		throw Error::Simple( 'HG: copy '.$from.' to '.$to.' failed: '.$! );
	}

	my ( $cmd, $gitOutput );
	my $gitComment = "TW_Copy: $from -> $to";
	
	$cmd = $Foswiki::cfg{Git}{ciCmd};
		( $gitOutput, $exit ) = Foswiki::Plugins::GitPlugin::GitRun::render(
						$Foswiki::cfg{Git}{ciCmd},
						FILENAME => $to,
						COMMENT => $gitComment );

	$gitOutput ||= '';

	if( $exit ) {
		throw Error::Simple($cmd.' failed: '.$exit.' '.$gitOutput );
	}
}

=pod

---++ _localCopyFile( $from, $to )
This is not for Git using but some else codes, for example, RCS.

=cut
sub _localCopyFile {
    my( $from, $to ) = @_;

    _mkPathTo( $to );
    unless( File::Copy::copy( $from, $to ) ) {
        throw Error::Simple( 'RCS: copy '.$from.' to '.$to.' failed: '.$! );
    }

    return;
}


#######################     attachment     #######################

=pod

---++ ObjectMethod getAttachmentList($web, $topic)

returns {} of filename => { key => value, key2 => value } for any given web, topic
Ignores files starting with _ or ending with .orig

=cut
###Copy from RCS
sub getAttachmentList {
	my( $this, $web, $topic ) = @_;
	my $dir = dirForTopicAttachments($web, $topic);
		
    opendir DIR, $dir || return '';
    my %attachmentList = ();
    my @files = sort grep { m/^[^\.*_]/ } readdir( DIR );
    @files = grep { !/.*.orig/ } @files;
    foreach my $attachment ( @files ) {
    	my @stat = stat ($dir."/".$attachment);
        $attachmentList{$attachment} = _constructAttributesForAutoAttached($attachment, \@stat);
    }
    closedir( DIR );
    return %attachmentList;
}


###Copy from RCS
sub dirForTopicAttachments {
    my ($web, $topic ) = @_;
    return $Foswiki::cfg{PubDir}.'/'.$web.'/'.$topic;
}

sub addRevisionFromStream {
    my( $this, $stream, $comment, $user, $date ) = @_;

    return _localAddRevisionFromStream( @_ ) if ( _isLocalWeb( $this->{web} ) );
	
    $this->init();

    if( !$this->{version} )
	{
		my $tmp = $this->numRevisions();
		$this->{version} = $tmp + 1;
    }
    $this->_saveStream( $stream );
    $this->_ci( $comment, $user, $date );
}


sub _localAddRevisionFromStream{
    my( $this, $stream, $comment, $user, $date ) = @_;
    $this->_localInit();

    _lock( $this );
    _saveStream( $this, $stream );
    _localci( $this, $comment, $user, $date );
}


=pod

---++ ObjectMethod getStream() -> \*STREAM

Return a text stream that will supply the text stored in the topic.

=cut

sub getStream {
    my( $this ) = shift;
    my $strm;
    unless( open( $strm, '<'.$this->{file} )) {
        throw Error::Simple( 'HG: stream open '.$this->{file}.
                               ' failed: '.$! );
    }
    return $strm;
}


sub _saveStream {
    my( $this, $fh ) = @_;
    ASSERT($fh) if DEBUG;

    _mkPathTo( $this->{file} );
    open( F, '>'.$this->{file} ) ||
        throw Error::Simple( 'HG: open '.$this->{file}.' failed: '.$! );
    binmode( F ) ||
      throw Error::Simple( 'HG: failed to binmode '.$this->{file}.': '.$! );
    my $text;
    binmode(F);
    while( read( $fh, $text, 1024 )) {
        print F $text;
    }
    close(F) ||
        throw Error::Simple( 'HG: close '.$this->{file}.' failed: '.$! );;

    if ( _isLocalWeb( $this->{web} ) )
    {
	chmod( $Foswiki::cfg{RCS}{filePermission}, $this->{file} );
	return '';
    }

    chmod( $Foswiki::cfg{Git}{filePermission}, $this->{file} );

    #Judge whether the web is not to use Git.

	#???
	my ( $gitOutput, $exit ) =
	Foswiki::Plugins::GitPlugin::GitRun::render(
			$Foswiki::cfg{Git}{initCmd}, FILENAME => $this->{relfile} );
	if( $exit ) {
	    throw Error::Simple( $Foswiki::cfg{Git}{initCmd}.
		    ' of '.$this->_hidePath($this->{file}).
		    ' failed: '.$gitOutput );
	}
    return '';
}


=pod

sub _constructAttributesForAutoAttached
as long as stat is defined, return an emulated set of attributes for that attachment.

=cut

sub _constructAttributesForAutoAttached {
    my ($file, $stat) = @_;

    my %pairs = (
        name    => $file,
        version => '',
        path    => $file,
        size    => $stat->[7],
        date    => $stat->[9], 
#        user    => 'UnknownUser',  #safer _not_ to default - Foswiki will fill it in when it needs to
        comment => '',
        attr    => '',
        autoattached => '1'
       );

    if ($#$stat > 0) {
        return \%pairs;
    } else {
        return;
    }
}

=pod

---++ ObjectMethod moveAttachment( $newWeb, $newTopic, $newAttachment )
Move an attachment from one topic to another. The name is retained.

=cut

sub moveAttachment {
    my( $this, $newWeb, $newTopic, $newAttachment ) = @_;

    # FIXME might want to delete old directories if empty
    my $new = Foswiki::Store::Git->new( $this->{session}, $newWeb,
                                          $newTopic, $newAttachment );

    #Judeg from web and to web, all will use Git, or all will not , or one will and one will not.
    if ( _isLocalWeb( $this->{web} ) and ( _isLocalWeb( $new->{web} ) or $newWeb eq $Foswiki::cfg{TrashWebName} ) )
    {
	_localMoveFile( $this, $this->{file}, $new->{file} );

    	if( -e $this->{rcsFile} ) {
	    _localMoveFile( $this, $this->{rcsFile}, $new->{rcsFile} );
	}
    }
    elsif ( !_isLocalWeb( $this->{web} ) and !_isLocalWeb( $new->{web} ) )
    {
    	_moveFile( $this->{gitfile}, $new->{gitfile} );
    }
    else
    {
		my $info = "could not move attachment $this->{attachment} from !$this->{web} to !$newWeb, because one is out-sync web and the other is not.";
        throw Error::Simple( "permission deney:".$info );
    }
}

=pod

---++ ObjectMethod moveAttachment( $newWeb, $newTopic, $newAttachment )
Copy an attachment from one topic to another.

=cut
sub copyAttachment {
    my( $this, $newWeb, $newTopic ) = @_;

    my $oldWeb = $this->{web};
    my $oldTopic = $this->{topic};
    my $attachment = $this->{attachment};

    my $new = Foswiki::Store::Git->new( $this->{session}, $newWeb, $newTopic, $attachment );

    #Judge whether the web will use the Git.
    if( _isLocalWeb( $new->{web} ) )
    {
	_localCopyFile( $this->{file}, $new->{file} );

	if( -e $this->{rcsFile} ) {
        _localCopyFile( $this->{rcsFile}, $new->{rcsFile} );
   	}
    }
    else
    {
    	_copyFile( $this,$this->{file}, $new->{gitfile} );
    }

    return;
}


#######################     Web     #######################

=pod

---++ ObjectMethod getWebNames() -> @webs
Gets a list of names of subwebs in the current web

=cut
###Copy from RCS
sub getWebNames {
    my $this = shift;
    my $dir = $Foswiki::cfg{DataDir}.'/'.$this->{web};
    if( opendir( DIR, $dir ) ) {
        my @tmpList =
          sort
            map { Foswiki::Sandbox::untaintUnchecked( $_ ) }
              grep { !/\./ &&
                     !/$Foswiki::cfg{NameFilter}/ &&
                     -d $dir.'/'.$_
                   }
                readdir( DIR );
        closedir( DIR );
        return @tmpList;
    }
    return ();
}

=pod

---++ ObjectMethod removeWeb( $web )
   * =$web= - web being removed

Destroy a web, utterly. Removed the data and attachments in the web.

Use with great care! No backup is taken!

=cut

sub removeWeb {
    my $this = shift;

    # Just make sure of the context
    ASSERT(!$this->{topic}) if DEBUG;

    _rmtree( $Foswiki::cfg{DataDir}.'/'.$this->{web} );
    _rmtree( $Foswiki::cfg{PubDir}.'/'.$this->{web} );
}

=pod

---++ ObjectMethod moveWeb(  $newWeb )
Move a web.

=cut

sub moveWeb {
    my( $this, $newWeb ) = @_;

    #Judeg from web and to web, all will use Git, or all will not , or one will and one will not.
    if ( _isLocalWeb( $this->{web} ) and _isLocalWeb( $newWeb ) )
    {
	_localMoveFile( $this,
		$Foswiki::cfg{DataDir}.'/'.$this->{web},
               	$Foswiki::cfg{DataDir}.'/'.$newWeb );
    	if( -d $Foswiki::cfg{PubDir}.'/'.$this->{web} )
	{
        	_localMoveFile( $this,
			$Foswiki::cfg{PubDir}.'/'.$this->{web},
                   	$Foswiki::cfg{PubDir}.'/'.$newWeb );
      	}
    }
    elsif( !_isLocalWeb( $this->{web} ) and !_isLocalWeb( $newWeb ) )
    {
    	_moveFile( $Foswiki::cfg{Git}{root}.'/'.'data'.'/'.$this->{web},
               	$Foswiki::cfg{Git}{root}.'/'.'data'.'/'.$newWeb );

	my $FoswikiPath = $Foswiki::cfg{DataDir};
        $FoswikiPath =~ s/\/[^\/]*$//;
        my $GitPath = $Foswiki::cfg{Git}{root};
        $GitPath =~ s/\/$//;
	#deal soft link if need;
        if ( $FoswikiPath ne $GitPath )
        {
		_rmLink( $this->{web}, 'Data' ) unless ( $this->{web} =~ m/\// );
                _mkLink( $newWeb, 'Data' ) unless ( $newWeb =~ m/\// );
        }

    	if( -d $Foswiki::cfg{Git}{root}.'/'.'pub'.'/'.$this->{web} )
	{
        	_moveFile( $Foswiki::cfg{Git}{root}.'/'.'pub'.'/'.$this->{web},
                	$Foswiki::cfg{Git}{root}.'/'.'pub'.'/'.$newWeb );
		if ( $FoswikiPath ne $GitPath )
	        {
                	_rmLink( $this->{web}, 'Pub' ) unless ( $this->{web} =~ m/\// );
        	        _mkLink( $newWeb, 'Pub' ) unless ( $newWeb =~ m/\// );
	        }

        }
    }
    else
    {
	my $info = "could not move !$this->{web} to !$newWeb, because one is out-sync web and the other is not.";
        throw Error::Simple( "permission deney:".$info );
    }
}

sub _rmLink{
	my ( $web, $directory ) = @_;
	$directory .= 'Dir';
	unlink $Foswiki::cfg{$directory}.'/'.$web;	#remove soft link
}

sub _mkLink{
	my ( $newWeb, $directory ) = @_;	#$directory = Data or Pub
	my $little = $directory;
	$little =~ s/(.*)/\L$1/;	#Data->data   Pub->pub
	$directory .= 'Dir';
	my $target = $Foswiki::cfg{Git}{root}.'/'.$little.'/'.$newWeb;
	my $link = $Foswiki::cfg{$directory}.'/'.$newWeb;
	symlink $target, $link;		#make soft link
}

# remove a directory and all subdirectories.
#???
sub _rmtree {
    my $root = shift;

    if( opendir(my $D, $root ) ) {
        foreach my $entry ( grep { !/^\.+$/ } readdir( $D ) ) {
            $entry =~ /^(.*)$/;
            $entry = $root.'/'.$1;
            if( -d $entry ) {
                _rmtree( $entry );
            } elsif( !unlink( $entry ) && -e $entry ) {
                if ($Foswiki::cfg{OS} ne 'WINDOWS') {
                    throw Error::Simple( 'RCS: Failed to delete file '.
                                           $entry.': '.$! );
                } else {
                    # Windows sometimes fails to delete files when
                    # subprocesses haven't exited yet, because the
                    # subprocess still has the file open. Live with it.
                    print STDERR 'WARNING: Failed to delete file ',
                                           $entry,": $!\n";
                }
            }
        }
        closedir($D);

        if (!rmdir( $root )) {
            if ($Foswiki::cfg{OS} ne 'WINDOWS') {
                throw Error::Simple( 'RCS: Failed to delete '.$root.': '.$! );
            } else {
                print STDERR 'WARNING: Failed to delete '.$root.': '.$!,"\n";
            }
        }
    }
    return;
}


#######################     Search     #######################


=pod

---++ ObjectMethod searchInWebContent($searchString, $web, \@topics, \%options ) -> \%map

Search for a string in the content of a web. The search must be over all
content and all formatted meta-data, though the latter search type is
deprecated (use searchMetaData instead).

   * =$searchString= - the search string, in egrep format if regex
   * =$web= - The web to search in
   * =\@topics= - reference to a list of topics to search
   * =\%options= - reference to an options hash
The =\%options= hash may contain the following options:
   * =type= - if =regex= will perform a egrep-syntax RE search (default '')
   * =casesensitive= - false to ignore case (defaulkt true)
   * =files_without_match= - true to return files only (default false)

The return value is a reference to a hash which maps each matching topic
name to a list of the lines in that topic that matched the search,
as would be returned by 'grep'. If =files_without_match= is specified, it will
return on the first match in each topic (i.e. it will return only one
match per topic, and will not return matching lines).

=cut

sub searchInWebContent {
    my( $this, $searchString, $topics, $options ) = @_;
    ASSERT(defined $options) if DEBUG;
    my $type = $options->{type} || '';

    # I18N: 'grep' must use locales if needed,
    # for case-insensitive searching.  See Foswiki::setupLocale.
    my $program = '';
    # FIXME: For Cygwin grep, do something about -E and -F switches
    # - best to strip off any switches after first space in
    # EgrepCmd etc and apply those as argument 1.
    if( $type eq 'regex' ) {
        $program = $Foswiki::cfg{Git}{EgrepCmd};
    } else {
        $program = $Foswiki::cfg{Git}{FgrepCmd};
    }

    $program =~ s/%CS{(.*?)\|(.*?)}%/$options->{casesensitive}?$1:$2/ge;
    $program =~ s/%DET{(.*?)\|(.*?)}%/$options->{files_without_match}?$2:$1/ge;

    my $sDir = $Foswiki::cfg{DataDir}.'/'.$this->{web}.'/';
    my $seen = {};
    # process topics in sets, fix for Codev.ArgumentListIsTooLongForSearch
    my $maxTopicsInSet = 512; # max number of topics for a grep call
    my @take = @$topics;
    my @set = splice( @take, 0, $maxTopicsInSet );
    my $sandbox = $this->{session}->{sandbox};
    while( @set ) {
        @set = map { "$sDir/$_.txt" } @set;
        my ($matches, $exit ) = $Foswiki::sandbox->sysCommand(
            $program,
            TOKEN => $searchString,
            FILES => \@set);
        foreach my $match ( split( /\r?\n/, $matches )) {
            if( $match =~ m/([^\/]*)\.txt(:(.*))?$/ ) {
                push( @{$seen->{$1}}, $3 );
            }
        }
        @set = splice( @take, 0, $maxTopicsInSet );
    }
    return $seen;
}


sub _isLocalWeb{
        my ( $rootWeb ) = @_;
        my @localWeb = split ( /\s*,\s*/, $Foswiki::cfg{Git}{outSync} );
	push @localWeb, $Foswiki::cfg{Git}{LocalTrashWebName};

	$rootWeb =~ s/(.*?)\/(.*)/$1/;
    
        my $isLocal = 0; 
        foreach my $localWeb (@localWeb)
        {
                if ( $rootWeb eq $localWeb )
                {
                        $isLocal = 1;
                        last;
                }
        }

        return $isLocal;
}


#######################     Others     #######################

=pod

---++ ObjectMethod setLease( $lease )
   * =$lease= reference to lease hash, or undef if the existing lease is to be cleared.

Set an lease on the topic.

=cut

sub setLease {
    my( $this, $lease ) = @_;

    my $filename = $this->_controlFileName('lease');
    if( $lease ) {
        $this->_saveFile( $filename, join( "\n", %$lease ) );
    } elsif( -e $filename ) {
        unlink $filename ||
          throw Error::Simple( 'HG: failed to delete '.$filename.': '.$! );
    }
}


=pod

---++ ObjectMethod getLease() -> $lease

Get the current lease on the topic.

=cut

sub getLease {
    my( $this ) = @_;

    my $filename = $this->_controlFileName('lease');
    if ( -e $filename ) {
        my $t = $this->_readFile( $filename );
        my $lease = { split( /\r?\n/, $t ) };
        return $lease;
    }

    return undef;
}


# filenames for lock and lease files
sub _controlFileName {
    my( $this, $type ) = @_;

    my $fn = $this->{file};
    $fn =~ s/txt$/$type/;
    return $fn;
}


=pod
---++ init()
used to create a new file without content similar as `touch`, and add to repository, using this function before a new topic/attachment.
=cut
sub init {
    my $this = shift;

    return _localInit( @_ ) if ( _isLocalWeb( $this->{web} ) );

    return unless $this->{topic};

    unless( -e $this->{file} ) {
		_mkPathTo( $this->{file} );
		# "touch" file to create it
		open FILE, ">$this->{file}";
		close FILE;
		#git add command
		my ( $gitOutput, $exit ) =
			Foswiki::Plugins::GitPlugin::GitRun::render(
				$Foswiki::cfg{Git}{initCmd}, FILENAME => $this->{relfile} );
		if( $exit ) {
			throw Error::Simple( $Foswiki::cfg{Git}{initCmd}.
				' of '.$this->_hidePath($this->{file}).
				' failed: '.$gitOutput );
		}
    }
}


=pod

---++ _localInit( $this )
Initialize the file in repository. This is not for Git using but some else codes, for example, RCS.

=cut
sub _localInit{
	my $this = shift;

	return unless $this->{topic};

	unless( -e $this->{file} ) {
		if( $this->{attachment} && !$this->isAsciiDefault() )
		{
            		$this->initBinary();
        	}
		else
		{
            		$this->initText();
        	}
	}


	return;
}


=pod
---++ ci
commit file to repository
=cut 
sub _ci {
	my( $this, $comment, $user, $date ) = @_;

	#Judge whether the web will use Git.
	return _localci( @_ ) if ( _isLocalWeb( $this->{web} ) );

	unless(defined $date)
	{
		$date = time();
	}
	$comment ||= '';

	#you can't change the arguments' order before you know _getVersionArray()
	#'\n'can't be instead of '\t', but why?
	my $gitComment = "TW_Version:$this->{version}\tTW_Author:$this->{session}->{user}\tTW_Path:$this->{relfile}\tTW_Comment:$comment\tTW_Date:$date";

	my( $cmd, $gitOutput, $exit );
	chmod( $Foswiki::cfg{Git}{filePermission}, $this->{file} );

	$cmd = $Foswiki::cfg{Git}{ciCmd};
	( $gitOutput, $exit ) = Foswiki::Plugins::GitPlugin::GitRun::render(
					       $Foswiki::cfg{Git}{ciCmd},
					       USERNAME => $user,
					       FILENAME => $this->{relfile},
					       COMMENT => $gitComment );

	$gitOutput ||= '';

	if( $exit ) {
        	throw Error::Simple($cmd.' of '.$this->_hidePath($this->{file}).
                              ' failed: '.$exit.' '.$gitOutput );
	}
}

=pod

---++ _localci($comment, $user, $date)
check in the repository. This is not for Git using but some else codes, for example, RCS.
=cut
sub _localci{
    my( $this, $comment, $user, $date ) = @_;

    $comment = 'none' unless $comment;

    my( $cmd, $rcsOutput, $exit );
    if( defined( $date )) {
        require Foswiki::Time;
        $date = Foswiki::Time::formatTime( $date , '$rcs', 'gmtime');
        $cmd = $Foswiki::cfg{RCS}{ciDateCmd};
        ($rcsOutput, $exit)= $Foswiki::sandbox->sysCommand(
            $cmd,
            USERNAME => $user,
            FILENAME => $this->{file},
            COMMENT => $comment,
            DATE => $date );
    } else {
        $cmd = $Foswiki::cfg{RCS}{ciCmd};
        ($rcsOutput, $exit)= $Foswiki::sandbox->sysCommand(
            $cmd,
            USERNAME => $user,
            FILENAME => $this->{file},
            COMMENT => $comment );
    }
    $rcsOutput ||= '';

    if( $exit ) {
        throw Error::Simple($cmd.' of '.$this->hidePath($this->{file}).
                              ' failed: '.$exit.' '.$rcsOutput );
    }

    chmod( $Foswiki::cfg{RCS}{filePermission}, $this->{file} );
}


sub _mkPathTo {
    my( $file ) = @_;

    $file = Foswiki::Sandbox::untaintUnchecked( $file ); 

    my $path = File::Basename::dirname($file);
    eval {
        File::Path::mkpath($path, 0,$Foswiki::cfg{Git}{dirPermission});
    };
	chmod(0775,$path);
    if ($@) {
       throw Error::Simple("HG: failed to create ${path}: $!");
    }
}

=pod

---++ ObjectMethod isAsciiDefault (   ) -> $boolean

Check if this file type is known to be an ascii type file.

=cut

sub isAsciiDefault {
    my $this = shift;
    return ( $this->{attachment} =~
               /$Foswiki::cfg{RCS}{asciiFileSuffixes}/ );
}


=pod

---++ ObjectMethod isLocked( ) -> ($user, $time)

See if a foswiki lock exists. Return the lock user and lock time if it does.

=cut

sub isLocked {
    my( $this ) = @_;

    my $filename = $this->_controlFileName('lock');
    if ( -e $filename ) {
        my $t = $this->_readFile( $filename );
        return split( /\s+/, $t, 2 );
    }
    return ( undef, undef );
}

=pod

---++ ObjectMethod setLock($lock, $user)

Set a lock on the topic, if $lock, otherwise clear it.
$user is a wikiname.

SMELL: there is a tremendous amount of potential for race
conditions using this locking approach.

=cut

sub setLock {
    my( $this, $lock, $user ) = @_;

    $user = $this->{session}->{user} unless $user;

    my $filename = $this->_controlFileName('lock');
    if( $lock ) {
        my $lockTime = time();
        $this->_saveFile( $filename, $user."\n".$lockTime );
    } else {
        unlink $filename ||
          throw Error::Simple( 'HG: failed to delete '.$filename.': '.$! );
    }
}

# Chop out recognisable path components to prevent hacking based on error
# messages
sub _hidePath {
    my ( $this, $erf ) = @_;
    $erf =~ s#.*(/\w+/\w+\.[\w,]*)$#...$1#;
    return $erf;
}

=pod

---+++ ObjectMethod getWorkArea( $key ) -> $directorypath

Gets a private directory uniquely identified by $key. The directory is
intended as a work area for plugins.

The standard is a directory named the same as "key" under
$Foswiki::cfg{Git}{WorkAreaDir}

SMELL should this be under Git control as well? If not it can't be distributed

=cut

sub getWorkArea {
    my( $this, $key ) = @_;

    # untaint and detect nasties
    $key = Foswiki::Sandbox::normalizeFileName( $key );
    throw Error::Simple( "Bad work area name $key" ) unless ( $key );

    #my $dir =  "$Foswiki::cfg{Git}{WorkAreaDir}/$key";
    my $dir =  "$Foswiki::cfg{WorkingDir}/work_areas/$key";

    unless( -d $dir ) {
        mkdir( $dir ) || throw Error::Simple(
            'HG: failed to create '.$key.':'.$dir .'work area: '.$! );
    }
    return $dir;
}

=pod

---++ ObjectMethod recordChange($user, $rev, $more)
Record that the file changed

=cut
sub recordChange {
    my( $this, $user, $rev, $more ) = @_;
    $rev = 1 unless defined $rev;
    $more ||= '';

    # Store wikiname in the change log
    $user = $this->{session}->{users}->getWikiName( $user );

    my $file = $Foswiki::cfg{DataDir}.'/'.$this->{web}.'/.changes';
    return unless( !-e $file || -w $file ); # no point if we can't write it

    my @changes =
      map {
          my @row = split(/\t/, $_, 5);
          \@row }
        split( /[\r\n]+/, _readFile( $this, $file ));

    # Forget old stuff
    my $cutoff = time() - $Foswiki::cfg{Store}{RememberChangesFor};
    while (scalar(@changes) && $changes[0]->[2] < $cutoff) {
        shift( @changes );
    }

    # Add the new change to the end of the file
    push( @changes, [ $this->{topic}, $user, time(), $rev, $more ] );
    my $text = join( "\n", map { join( "\t", @$_); } @changes );

	$this->_saveFile( $file, $text );
    return;
}

=pod

---++ ObjectMethod eachChange($since) -> $iterator

Return iterator over changes - see Store for details

=cut
#???
sub eachChange {
    my( $this, $since ) = @_;
    my $file = $Foswiki::cfg{DataDir}.'/'.$this->{web}.'/.changes';
    require Foswiki::ListIterator;

    if( -r $file ) {
        # SMELL: could use a LineIterator to avoid reading the whole
        # file, but it hardle seems worth it.
        my @changes =
          map {
              # Create a hash for this line
              { topic => $_->[0], user => $_->[1], time => $_->[2],
                  revision => $_->[3], more => $_->[4] };
          }
            grep {
                # Filter on time
                $_->[2] && $_->[2] >= $since
            }
              map {
                  # Split line into an array
                  my @row = split(/\t/, $_, 5);
                  \@row;
              }
                reverse split( /[\r\n]+/, readFile( $this, $file ));

        return new Foswiki::ListIterator( \@changes );
    } else {
        my $changes = [];
        return new Foswiki::ListIterator( $changes );
    }
}

# implements RcsFile
sub initBinary {
    my( $this ) = @_;

    $this->{binary} = 1;

    _mkPathTo( $this->{file} );

    return if -e $this->{rcsFile};

    my ( $rcsOutput, $exit ) =
      $Foswiki::sandbox->sysCommand(
          $Foswiki::cfg{RCS}{initBinaryCmd}, FILENAME => $this->{file} );
    if( $exit ) {
        throw Error::Simple( $Foswiki::cfg{RCS}{initBinaryCmd}.
                               ' of '.$this->hidePath($this->{file}).
                                 ' failed: '.$rcsOutput );
    } elsif( ! -e $this->{rcsFile} ) {
        # Sometimes (on Windows?) rcs file not formed, so check for it
        throw Error::Simple( $Foswiki::cfg{RCS}{initBinaryCmd}.
                               ' of '.$this->hidePath($this->{rcsFile}).
                                 ' failed to create history file');
    }
}

# implements RcsFile
sub initText {
    my( $this ) = @_;

    $this->{binary} = 0;

    _mkPathTo( $this->{file} );

    return if -e $this->{rcsFile};

    my ( $rcsOutput, $exit ) =
      $Foswiki::sandbox->sysCommand
        ( $Foswiki::cfg{RCS}{initTextCmd},
          FILENAME => $this->{file} );
    if( $exit ) {
        $rcsOutput ||= '';
        throw Error::Simple( $Foswiki::cfg{RCS}{initTextCmd}.
                               ' of '.$this->hidePath($this->{file}).
                                 ' failed: '.$rcsOutput );
    } elsif( ! -e $this->{rcsFile} ) {
        # Sometimes (on Windows?) rcs file not formed, so check for it
        throw Error::Simple( $Foswiki::cfg{RCS}{initTextCmd}.
                               ' of '.$this->hidePath($this->{rcsFile}).
                                 ' failed to create history file');
    }
}


sub _lock {
    my $this = shift;

    return unless -e $this->{rcsFile};

    # Try and get a lock on the file
    my ($rcsOutput, $exit) = $Foswiki::sandbox->sysCommand(
        $Foswiki::cfg{RCS}{lockCmd}, FILENAME => $this->{file} );

    if( $exit ) {
        # if the lock has been set more than 24h ago, let's try to break it
        # and then retry.  Should not happen unless in Cairo upgrade
        # scenarios - see Item2102
        if ((time - (stat($this->{rcsFile}))[9]) > 3600) {
            warn 'Automatic recovery: breaking lock for ' . $this->{file} ;
            $Foswiki::sandbox->sysCommand(
                $Foswiki::cfg{RCS}{breaklockCmd}, FILENAME => $this->{file} );
        ($rcsOutput, $exit) = $Foswiki::sandbox->sysCommand(
                $Foswiki::cfg{RCS}{lockCmd}, FILENAME => $this->{file} );
        }
       if ( $exit ) {
           # still no luck - bailing out
           $rcsOutput ||= '';
           throw Error::Simple( 'RCS: '.$Foswiki::cfg{RCS}{lockCmd}.
                                ' failed: '.$rcsOutput );
       }
    }
    chmod( $Foswiki::cfg{RCS}{filePermission}, $this->{file} );
}



# Chop out recognisable path components to prevent hacking based on error
# messages
sub hidePath {
    my ( $this, $erf ) = @_;
    $erf =~ s#.*(/\w+/\w+\.[\w,]*)$#...$1#;
    return $erf;
}

sub _readTo {
    my( $file, $char ) = @_;
    my $buf = '';
    my $ch;
    my $space = 0;
    my $string = '';
    my $state = '';
    while( read( $file, $ch, 1 ) ) {
        if( $ch eq '@' ) {
            if( $state eq '@' ) {
                $state = 'e';
                next;
            } elsif( $state eq 'e' ) {
                $state = '@';
                $string .= '@';
                next;
            } else {
                $state = '@';
                next;
            }
        } else {
            if( $state eq 'e' ) {
                $state = '';
                if( $char eq '@' ) {
                    last;
                }
                # End of string
            } elsif ( $state eq '@' ) {
                $string .= $ch;
                next;
            }
        }
        if( $ch =~ /\s/ ) {
            if( length( $buf ) == 0 ) {
                next;
            } elsif( $space ) {
                next;
            } else {
                $space = 1;
                $ch = ' ';
            }
        } else {
            $space = 0;
        }
        $buf .= $ch;
        if( $ch eq $char ) {
            last;
        }
    }
    return( $buf, $string );
}


##########################
sub mkTmpFilename {
    my $tmpdir = File::Spec->tmpdir();
    my $file = _mktemp( 'foswikiAttachmentXXXXXX', $tmpdir );
    return File::Spec->catfile($tmpdir, $file);
}

# Adapted from CPAN - File::MkTemp
sub _mktemp {
    my ($template,$dir,$ext,$keepgen,$lookup);
    my (@template,@letters);

    ASSERT(@_ == 1 || @_ == 2 || @_ == 3) if DEBUG;

    ($template,$dir,$ext) = @_;
    @template = split //, $template;

    ASSERT($template =~ /XXXXXX$/) if DEBUG;

    if ($dir){
        ASSERT(-e $dir) if DEBUG;
    }

    @letters =
      split(//,'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ');

    $keepgen = 1;

    while ($keepgen){
        for (my $i = $#template; $i >= 0 && ($template[$i] eq 'X'); $i--){
            $template[$i] = $letters[int(rand 52)];
        }

        undef $template;

        $template = pack 'a' x @template, @template;

        $template = $template . $ext if ($ext);

        if ($dir){
            $lookup = File::Spec->catfile($dir, $template);
            $keepgen = 0 unless (-e $lookup);
        } else {
            $keepgen = 0;
        }

        next if $keepgen == 0;
    }

    return($template);
}


=pod

---++ ObjectMethod removeSpuriousLeases( $web )

Remove leases that are not related to a topic. These can get left behind in
some store implementations when a topic is created, but never saved.

=cut

sub removeSpuriousLeases {
    my( $this ) = @_;
    my $web = $Foswiki::cfg{DataDir}.'/'.$this->{web}.'/';
    my $W;
    if (opendir($W, $web)) {
        foreach my $f (readdir($W)) {
            if ($f =~ /^(.*)\.lease$/) {
                if (! -e "$1.txt,v") {
                    unlink($f);
                }
            }
        }
        closedir($W);
    }
    return;
}

=pod

---++ ObjectMethod stringify()

Generate string representation for debugging

=cut

sub stringify {
    my $this = shift;
    my @reply;
    foreach my $key qw(web topic attachment file rcsFile) {
        if (defined $this->{$key}) {
            push(@reply, "$key=$this->{$key}");
        }
    }
    return join(',', @reply);
}


# create web, LocalTrash, for local topics and attachments
sub _localCreateTrash{
	my $this = shift;

	my $TrashWebP = $Foswiki::cfg{DataDir}.'/'.$Foswiki::cfg{TrashWebName}.'/WebPreferences.txt';
	my $Pcontent = _readFile( $this, $TrashWebP);
	my $i=1;

	my $opts = {
		NEWWEB => $Foswiki::cfg{Git}{LocalTrashWebName},
		BASEWEB => $Foswiki::cfg{TrashWebName},
		ACTION => 'createweb',
		};

	my $tempP='';
	while(1)
	{   
        	$tempP = $Pcontent;
	        $Pcontent =~ s/($Foswiki::regex{setRegex}(.*?)\s*=)(.*?)$//m;
                last if $tempP eq $Pcontent;
	        $opts->{$3} = $4;
	}

	require Foswiki::Store;
	my $new = new Foswiki::Store( $this->{session} );
	$new->createWeb( $this->{session}->{user}, $Foswiki::cfg{Git}{LocalTrashWebName}, $Foswiki::cfg{TrashWebName}, $opts);

	return;
}


# use for Debug
sub writeDebug
{
	if( open( DEBUGLOG, ">>/tmp/git.debug") )
	{
		foreach (@_) {
			print DEBUGLOG "$_ ";
		}
		print DEBUGLOG "\n";
		close(DEBUGLOG);
	}
}

1;
