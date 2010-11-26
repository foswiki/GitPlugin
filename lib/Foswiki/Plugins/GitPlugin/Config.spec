# ---+ Extensions
# ---++ GitPlugin
# If you are a first-time installer; once you have set up the next
# paths below, your revision should work - try it. You can always come
# back and tweak other settings later.<p />

# **SELECT RcsWrap,RcsLite,Git**
# Default store implementation.
# <ul><li>RcsWrap uses normal RCS executables.</li>
# <li>RcsLite uses a 100% Perl simplified implementation of RCS.
# RcsLite is useful if you don't have, and can't install, RCS - for
# example, on a hosted platform. It will work, and is compatible with
# RCS, but is not quite as fast.</li></ul>
# You can manually add options to LocalSite.cfg to select a
# different store for each web. If $Foswiki::cfg{Store}{Fred} is defined, it will
# be taken as the name of a perl class (which must implement the methods of
# Foswiki::Store::RcsFile).
# The Foswiki::Store::Subversive class is an example implementation using the
# Subversion version control system as a data store.
$Foswiki::cfg{StoreImpl} = 'Git';

# **SELECT distributed,centralized**
# Foswiki on Git supports different ways to merge repositories.
# 'centralized' means that there is a backup repository, and each 
# foswiki fetches from it and push to it after a commit.
# 'distributed' means that each foswiki fetches from other the other 
# foswiki installations directly.
$Foswiki::cfg{Git}{mergeMode} = 'centralized';

# **PATH**
# The path of the git installation.
$Foswiki::cfg{Git}{Path} = '';

# **PATH**
# The path of the git repository installation; usually it is set to 
# the parent directory of data/ and pub/.
$Foswiki::cfg{Git}{root} = '';

# **STRING 30 **
# Any web listed here will not be added into the Git repository, 
# which means they are not synchronized to other sites (out-of-sync).
# This should be a comma-separated list of names webname1,webname2,webname3. 
$Foswiki::cfg{Git}{outSync} = 'System,Sandbox,Main';

# **STRING 20 EXPERT**
# Name of the Trash web for outSync webs (where deleted topics are moved).
# If you change this setting, you must ensure the web is out-of-Sync.
# This web will be created when you remove out-of-Sync topic or attachment, 
# if it does not exist.
$Foswiki::cfg{Git}{LocalTrashWebName} = 'TrashLocal';

# **PATH**
# The path of the ssh private key. Ensure that the private key has
# the correct permissions as defined in ssh.
$Foswiki::cfg{Git}{SSHKey} = '';

# ---++ Git store settings
# If you select git as the Store setting, these settings need to
# be adjusted.

# **OCTAL**
# File security for new directories. You may have to adjust these
# permissions to allow (or deny) users other than the webserver user access
# to directories that Foswiki creates. This is an *octal* number
# representing the standard UNIX permissions (e.g. 755 == rwxr-xr-x)
$Foswiki::cfg{Git}{dirPermission}= 0755;

# **OCTAL**
# File security for new files. You may have to adjust these
# permissions to allow (or deny) users other than the webserver user access
# to files that Foswiki creates.  This is an *octal* number
# representing the standard UNIX permissions (e.g. 644 == rw-r--r--)
$Foswiki::cfg{Git}{filePermission}= 0755;

# **STRING 30 **
# The name of the remote sites to be synchronized, as a comma-separated
# list: sitename1,sitename2,sitename3. 
$Foswiki::cfg{Git}{remoteName} = '';

# **STRING 10  M**
# Name of the local git repository.
$Foswiki::cfg{Git}{LocalName} = '';

# **STRING 10  **
# Name of the central git repository.
$Foswiki::cfg{Git}{backupReposName} = '';

# **COMMAND EXPERT**
# Git initialise a file.
# %FILENAME|F% will be expanded to the filename.
$Foswiki::cfg{Git}{initCmd} = "add %FILENAME|F%";
# **COMMAND EXPERT**
# Git commit the file.
# %COMMENT|U% will be expanded to the comment.
$Foswiki::cfg{Git}{ciCmd} = "commit -m\"%COMMENT|U%\" %FILENAME|F%";
# **COMMAND EXPERT**
# Git commit the files that renamed together.
# Rename FILENAME1 to FILENAME2.
$Foswiki::cfg{Git}{mvciCmd} = "commit -m\"%COMMENT|U%\" %FILENAME1|F% %FILENAME2|F%";
# **COMMAND EXPERT**
# Git show a special revision of a special file.
# %SHA1% will be expanded to the SHA number
$Foswiki::cfg{Git}{coCmd} = "show %SHA1%:%FILENAME|F%";
# **COMMAND EXPERT**
# Git differences between two revisions.
# %REVISIONn|N% will be expanded to the revision number.
# %CONTEXT|N% will be expanded to the number of lines of context.
$Foswiki::cfg{Git}{diffCmd} = "diff --unified=%CONTEXT|N% %REVISION1%:%FILENAME1|F% %REVISION2%:%FILENAME2|F%";
# **COMMAND EXPERT**
# Git get the revision of file.
$Foswiki::cfg{Git}{numRevisions} = "log --follow %FILENAME|F%";
# **COMMAND EXPERT**
# Git get the revision of repository from {Store}{RememberChangesFor} seconds ago
$Foswiki::cfg{Git}{logCmd} = "log --since=\"%TIME% seconds ago\"";
# **COMMAND EXPERT**
# Git move a file, also rename.
# %SOURCE% is where file form.
# %DEST% is where file move to.
$Foswiki::cfg{Git}{moveCmd} = "mv %SOURCE% %DEST%";
# **COMMAND EXPERT**
# Git delete a file.
$Foswiki::cfg{Git}{removeCmd} = "rm %FILENAME|F%";
# **COMMAND EXPERT**
# Git read a special revision of file when deal with conflicts.
$Foswiki::cfg{Git}{readFileCmd} = "show %SHA1%";
# **COMMAND EXPERT**
# Git get remote site's repository.
$Foswiki::cfg{Git}{fetchCmd} = "fetch %SITENAME%";
# **COMMAND EXPERT**
# Git merge remote site's repository in distributed mode.
$Foswiki::cfg{Git}{mergeCmdDistributed} = "merge %SITENAME%/master";
# **COMMAND EXPERT**
# Git merge remote site's repository in centralized mode.
$Foswiki::cfg{Git}{mergeCmdCentralized} = "merge %SITENAME%";
# **COMMAND EXPERT**
# Git list unmered files when do merge.
# That means these files have conflicts.
$Foswiki::cfg{Git}{unmergeListCmd} = "ls-files --unmerged";
# **COMMAND EXPERT**
# Git get ancestor content of file when deal with conflicts.
$Foswiki::cfg{Git}{showAncestorConfictCmd} = "show :1:%FILENAME|F%";
# **COMMAND EXPERT**
# Git get local content of file when deal with conflicts.
$Foswiki::cfg{Git}{showHEADConfictCmd} = "show :2:%FILENAME|F%";
# **COMMAND EXPERT**
# Git get content of remote site's file when deal with conflicts.
$Foswiki::cfg{Git}{showMERGE_HEADConfictCmd} = "show :3:%FILENAME|F%";
# **COMMAND EXPERT**
# Git commit the files when finish the conflicts.
$Foswiki::cfg{Git}{mergeConfictCmd} = "commit -m\"merge\" ";
# **COMMAND EXPERT**
# Git show it's status.
$Foswiki::cfg{Git}{statusCmd} = "status";
# **COMMAND EXPERT**
# Git push local repository to backup repository.
$Foswiki::cfg{Git}{pushCmd} = "push %REPOSNAME% master:%LOCALNAME%";
# **COMMAND EXPERT**
# Git remote branchs' name.
$Foswiki::cfg{Git}{branchListCmd} = "branch -r";

# **COMMAND EXPERT**
# Full path to GNU-compatible egrep program.
# %CS{|-i}% will be expanded
# to -i for case-sensitive search or to the empty string otherwise.
# Similarly for %DET, which controls whether matching lines are required.
# (see the documentation on these options with GNU grep for details).
$Foswiki::cfg{Git}{EgrepCmd} = '/bin/grep -E %CS{|-i}% %DET{|-l}% -H -- %TOKEN|U% %FILES|F%';

# **COMMAND EXPERT**
# Full path to GNU-compatible fgrep program.
$Foswiki::cfg{Git}{FgrepCmd} = '/bin/grep -F %CS{|-i}% %DET{|-l}% -H -- %TOKEN|U% %FILES|F%';

# **PERL H**
# bin/gitop script registration - do not modify
$Foswiki::cfg{SwitchBoard}{gitop} = [ 'Foswiki::Plugins::GitPlugin::GitAction', 'oper', { oper => 1 } ];
1;
