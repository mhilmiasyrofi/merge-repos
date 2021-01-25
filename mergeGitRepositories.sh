#
################################################################################
## Script to merge multiple git repositories into a new repository
## - The new repository will contain a folder for every merged repository
## - The script adds remotes for every project and then merges in every branch
##   and tag. These are renamed to have the origin project name as a prefix
##
## Usage: mergeGitRepositories.sh <new_project> <my_repo_urls.lst>
## - where <new_project> is the name of the new project to create
## - and <my_repo_urls.lst> is a file contaning the URLs to the respositories
##   which are to be merged on separate lines.
##
## Author: Robert von Burg
##            eitch@eitchnet.ch
##
## Version: 0.3.2
## Created: 2018-02-05
##
################################################################################
#

# disallow using undefined variables
shopt -s -o nounset

# Script variables
declare SCRIPT_NAME="${0##*/}"
declare SCRIPT_DIR="$(cd ${0%/*} ; pwd)"
declare ROOT_DIR="$PWD"
IFS=$'\n'

# Detect proper usage
if [ "$#" -ne "2" ] ; then
  echo -e "ERROR: Usage: $0 <new_project> <my_repo_urls.lst>"
  exit 1
fi


## Script variables
PROJECT_NAME="${1}"
PROJECT_PATH="${ROOT_DIR}/${PROJECT_NAME}"
TIMESTAMP="$(date +%s)"
LOG_FILE="${ROOT_DIR}/${PROJECT_NAME}_merge.${TIMESTAMP}.log"
REPO_FILE="${2}"
REPO_URL_FILE="${ROOT_DIR}/${REPO_FILE}"


# Script functions
function failed() {
  echo -e "ERROR: Merging of projects failed:"
  echo -e "ERROR: Merging of projects failed:" >>${LOG_FILE} 2>&1
  echo -e "$1"
  exit 1
}

function commit_merge() {
  current_branch="$(git symbolic-ref HEAD 2>/dev/null)"
  if [[ ! -f ".git/MERGE_HEAD" ]] ; then
    echo -e "INFO:   No commit required."
    echo -e "INFO:   No commit required." >>${LOG_FILE} 2>&1
  else
    echo -e "INFO:   Committing ${sub_project}..."
    echo -e "INFO:   Committing ${sub_project}..." >>${LOG_FILE} 2>&1
    if ! git commit -m "[Project] Merged branch '$1' of ${sub_project}" >>${LOG_FILE} 2>&1 ; then
      failed "Failed to commit merge of branch '$1' of ${sub_project} into ${current_branch}"
    fi
  fi
}


# Make sure the REPO_URL_FILE exists
if [ ! -e "${REPO_URL_FILE}" ] ; then
  echo -e "ERROR: Repo file ${REPO_URL_FILE} does not exist!"
  exit 1
fi


# Make sure the required directories don't exist
if [ -e "${PROJECT_PATH}" ] ; then
  echo -e "ERROR: Project ${PROJECT_NAME} already exists!"
  exit 1
fi


# create the new project
echo -e "INFO: Logging to ${LOG_FILE}"
echo -e "INFO: Creating new git repository ${PROJECT_NAME}..."
echo -e "INFO: Creating new git repository ${PROJECT_NAME}..." >>${LOG_FILE} 2>&1
echo -e "===================================================="
echo -e "====================================================" >>${LOG_FILE} 2>&1
cd ${ROOT_DIR}
mkdir ${PROJECT_NAME}
cd ${PROJECT_NAME}
git init
echo "Initial Commit" > initial_commit
# Since this is a new repository we need to have at least one commit
# thus were we create temporary file, but we delete it again.
# Deleting it guarantees we don't have conflicts later when merging
git add initial_commit
git commit --quiet -m "[Project] Initial Master Repo Commit"
git rm --quiet initial_commit
git commit --quiet -m "[Project] Initial Master Repo Commit"
echo


# Merge all projects into the branches of this project
echo -e "INFO: Merging projects into new repository..."
echo -e "INFO: Merging projects into new repository..." >>${LOG_FILE} 2>&1
echo -e "===================================================="
echo -e "====================================================" >>${LOG_FILE} 2>&1
for url in $(cat ${REPO_URL_FILE}) ; do

  if [[ "${url:0:1}" == '#' ]] ; then
    continue
  fi

  # extract the name of this project
  export sub_project=${url##*/}
  sub_project=${sub_project%*.git}

  echo -e "INFO: Project ${sub_project}"
  echo -e "INFO: Project ${sub_project}" >>${LOG_FILE} 2>&1
  echo -e "----------------------------------------------------"
  echo -e "----------------------------------------------------" >>${LOG_FILE} 2>&1

  # Fetch the project
  echo -e "INFO:   Fetching ${sub_project}..."
  echo -e "INFO:   Fetching ${sub_project}..." >>${LOG_FILE} 2>&1
  git remote add "${sub_project}" "${url}"
  if ! git fetch --tags --quiet ${sub_project} >>${LOG_FILE} 2>&1 ; then
  	failed "Failed to fetch project ${sub_project}"
  fi

  # add remote branches
  echo -e "INFO:   Creating local branches for ${sub_project}..."
  echo -e "INFO:   Creating local branches for ${sub_project}..." >>${LOG_FILE} 2>&1
  while read branch ; do
    branch_ref=$(echo $branch | tr " " "\t" | cut -f 1)
    branch_name=$(echo $branch | tr " " "\t" | cut -f 2 | cut -d / -f 3-)

    echo -e "INFO:   Creating branch ${branch_name}..."
    echo -e "INFO:   Creating branch ${branch_name}..." >>${LOG_FILE} 2>&1

    # create and checkout new merge branch off of master
    if ! git checkout -b "${sub_project}/${branch_name}" master >>${LOG_FILE} 2>&1 ; then failed "Failed preparing ${branch_name}" ; fi
    if ! git reset --hard ; then failed "Failed preparing ${branch_name}" >>${LOG_FILE} 2>&1 ; fi
    if ! git clean -d --force ; then failed "Failed preparing ${branch_name}" >>${LOG_FILE} 2>&1 ; fi

    # Merge the project
    echo -e "INFO:   Merging ${sub_project}..."
    echo -e "INFO:   Merging ${sub_project}..." >>${LOG_FILE} 2>&1
    if ! git merge --allow-unrelated-histories --no-commit "remotes/${sub_project}/${branch_name}" >>${LOG_FILE} 2>&1 ; then
      failed "Failed to merge branch 'remotes/${sub_project}/${branch_name}' from ${sub_project}"
    fi

    # And now see if we need to commit (maybe there was a merge)
    commit_merge "${sub_project}/${branch_name}"

    # relocate projects files into own directory
    if [ "$(ls)" == "${sub_project}" ] ; then
      echo -e "WARN:   Not moving files in branch ${branch_name} of ${sub_project} as already only one root level."
      echo -e "WARN:   Not moving files in branch ${branch_name} of ${sub_project} as already only one root level." >>${LOG_FILE} 2>&1
    else
      echo -e "INFO:   Moving files in branch ${branch_name} of ${sub_project} so we have a single directory..."
      echo -e "INFO:   Moving files in branch ${branch_name} of ${sub_project} so we have a single directory..." >>${LOG_FILE} 2>&1
      mkdir ${sub_project}
      for f in $(ls -a) ; do
        if  [[ "$f" == "${sub_project}" ]] ||
            [[ "$f" == "." ]] ||
            [[ "$f" == ".." ]] ; then
          continue
        fi
        git mv -k "$f" "${sub_project}/"
      done

      # commit the moving
      if ! git commit --quiet -m  "[Project] Move ${sub_project} files into sub directory" ; then
        failed "Failed to commit moving of ${sub_project} files into sub directory"
      fi
    fi
    echo
  done < <(git ls-remote --heads ${sub_project})


  # checkout master of sub probject
  if ! git checkout "${sub_project}/master" >>${LOG_FILE} 2>&1 ; then
    failed "sub_project ${sub_project} is missing master branch!"
  fi

  # copy remote tags
  echo -e "INFO:   Copying tags for ${sub_project}..."
  echo -e "INFO:   Copying tags for ${sub_project}..." >>${LOG_FILE} 2>&1
  while read tag ; do
    tag_ref=$(echo $tag | tr " " "\t" | cut -f 1)
    tag_name_unfixed=$(echo $tag | tr " " "\t" | cut -f 2 | cut -d / -f 3)

    # hack for broken tag names where they are like 1.2.0^{} instead of just 1.2.0
    tag_name="${tag_name_unfixed%%^*}"

    tag_new_name="${sub_project}/${tag_name}"
    echo -e "INFO:     Copying tag ${tag_name_unfixed} to ${tag_new_name} for ref ${tag_ref}..."
    echo -e "INFO:     Copying tag ${tag_name_unfixed} to ${tag_new_name} for ref ${tag_ref}..." >>${LOG_FILE} 2>&1
    if ! git tag "${tag_new_name}" "${tag_ref}" >>${LOG_FILE} 2>&1 ; then
      echo -e "WARN:     Could not copy tag ${tag_name_unfixed} to ${tag_new_name} for ref ${tag_ref}"
      echo -e "WARN:     Could not copy tag ${tag_name_unfixed} to ${tag_new_name} for ref ${tag_ref}" >>${LOG_FILE} 2>&1
    fi
  done < <(git ls-remote --tags --refs ${sub_project})

  # Remove the remote to the old project
  echo -e "INFO:   Removing remote ${sub_project}..."
  echo -e "INFO:   Removing remote ${sub_project}..." >>${LOG_FILE} 2>&1
  git remote rm ${sub_project}

  echo
done


# Now merge all project master branches into new master
git checkout --quiet master
echo -e "INFO: Merging projects master branches into new repository..."
echo -e "INFO: Merging projects master branches into new repository..." >>${LOG_FILE} 2>&1
echo -e "===================================================="
echo -e "====================================================" >>${LOG_FILE} 2>&1
for url in $(cat ${REPO_URL_FILE}) ; do

  if [[ ${url:0:1} == '#' ]] ; then
    continue
  fi

  # extract the name of this project
  export sub_project=${url##*/}
  sub_project=${sub_project%*.git}

  echo -e "INFO:   Merging ${sub_project}..."
  echo -e "INFO:   Merging ${sub_project}..." >>${LOG_FILE} 2>&1
  if ! git merge --allow-unrelated-histories --no-commit "${sub_project}/master" >>${LOG_FILE} 2>&1 ; then
    failed "Failed to merge branch ${sub_project}/master into master"
  fi

  # And now see if we need to commit (maybe there was a merge)
  commit_merge "${sub_project}/master"

  echo
done


# Done
cd ${ROOT_DIR}
echo -e "INFO: Done."
echo -e "INFO: Done." >>${LOG_FILE} 2>&1
echo

exit 0
