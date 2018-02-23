if [ $1 = 'jackrabbit' ]; then
    echo "jackrabbit"
    PROJECT=~/code_clones/jackrabbit
    TARGET_DIR=~/code_clones/jackrabbit_versions
    TMP_DIR=~/code_clones/jackrabbit_tmp
    START_TAG='jackrabbit-2.14.0'
    RC_TAGS='s/[-]rc[0-9]*|[-]b[0-9]+$//g'
    SEL_TAGS=''
elif [ $1 = 'maven' ]; then
    PROJECT=~/code_clones/maven
    TARGET_DIR=~/code_clones/maven_versions
    TMP_DIR=~/code_clones/maven_tmp
    START_TAG='maven-3.5.0'
    RC_TAGS='s/[-]RC[0-9]*//g'
    SEL_TAGS=''
elif [ $1 = 'ant' ]; then
    PROJECT=~/code_clones/ant
    TARGET_DIR=~/code_clones/ant_versions
    TMP_DIR=~/code_clones/ant_tmp
    START_TAG='ANT_1.10.0_RC1'
    RC_TAGS='s/_RC[0-9]*|[_]*B[0-9]*|[_]*FINAL|_MAIN_MERGE[0-9]*|_MAIN|_MERGE[0-9]*//g'
    SEL_TAGS='ANT_[0-9]+|ANT_MAIN_[0-9]*'
elif [ $1 = 'camel' ]; then
    PROJECT=~/code_clones/camel
    TARGET_DIR=~/code_clones/camel_versions
    TMP_DIR=~/code_clones/camel_tmp
    START_TAG='camel-2.18.3'
    RC_TAGS='s/[-]RC[0-9]*//g'
    SEL_TAGS='camel[-]'
elif [ $1 = 'tomcat80' ]; then
    PROJECT=~/code_clones/tomcat80
    TARGET_DIR=~/code_clones/tomcat80_versions
    TMP_DIR=~/code_clones/tomcat80_tmp
    START_TAG='TOMCAT_8_0_43'
    RC_TAGS='s/_RC[0-9]*//g'
    SEL_TAGS='TOMCAT_'
elif [ $1 = 'pig' ]; then
    echo "pig"
    PROJECT=~/code_clones/pig
    TARGET_DIR=~/code_clones/pig_versions
    TMP_DIR=~/code_clones/pig_tmp
    START_TAG='release-0.16.0'
    RC_TAGS='s/[-]rc[0-9]*|[.]new//g'
    SEL_TAGS='release'
fi




cd $PROJECT


if [ "$SEL_TAGS" != "" ]; then
    echo 'CommiterDate,GitCommit,Version' > $PROJECT.tag_commits.csv
    git log --pretty='%ci,%H' $START_TAG | git name-rev --stdin | grep 'tags' | tr '^' '~' | sed 's/ (tags\//,/g' | sed 's/)$//g' | sed 's/~/,/g' | grep -E $SEL_TAGS | cut -d',' -f1-3 |sort -n -t',' -k3,1 >> $PROJECT.tag_commits.csv
else
  echo 'CommiterDate,GitCommit,Version,Counter' > $PROJECT.tag_commits.csv
  git log --pretty='%ci,%H' $START_TAG | git name-rev --stdin | grep 'tags' | tr '^' '~' | sed 's/ (tags\//,/g' | sed 's/)$//g' | sed 's/~/,/g' | cut -d',' -f1-3 | sort -n -t',' -k3,1 >> $PROJECT.tag_commits.csv
  
fi

# Include the commits tagged as RC versions into the commits of the official version
if [ "$RC_TAGS" != "" ]; then
echo 'Remove rc tags'
sed -E -i $RC_TAGS $PROJECT.tag_commits.csv
fi

if [ $1 = 'camel' ]; then
echo 'For camel 2.0 -> 2.0.0'
sed -E -i 's/-2.0$/-2.0.0/g' $PROJECT.tag_commits.csv
fi

# These versions use the RC versions as a official version
if [ $1 = 'ant' ]; then
echo 'For ant rename tags ANT_15, ANT_16, ANT_197, ANT_198, ANT_1.10.0'
sed -i 's/ANT_15/ANT_15_B1/g' $PROJECT.tag_commits.csv
sed -i 's/ANT_16/ANT_16_B1/g' $PROJECT.tag_commits.csv 
sed -i 's/ANT_197/ANT_197_RC1/g' $PROJECT.tag_commits.csv 
sed -i 's/ANT_198/ANT_198_RC1/g' $PROJECT.tag_commits.csv 
sed -i 's/ANT_1.10.0/ANT_1.10.0_RC1/g' $PROJECT.tag_commits.csv 
fi

if [ $1 = 'jackrabbit' ]; then
echo 'Remove ver1.6'
sed -i '/1.6.0/d' $PROJECT.tag_commits.csv
fi

git tag > $PROJECT.all_tags.csv

RELS=`tail -n+2 $PROJECT.tag_commits.csv | awk -F, '{if (a[$3] < $1)a[$3]=$1;}END{for(i in a){print a[i]","i;}}' | sort -t',' -k1| cut -d ',' -f2`
echo $RELS
for r in $RELS; do
    check=`grep -x $r $PROJECT.all_tags.csv`
    if [ "$check" != "$r" ]; then
        echo 'CANNOT find '$r' in tags'
        echo 'CANNOT find '$r' in tags' >> $PROJECT.errors
    fi
done

if [ -f "$PROJECT.errors" ]; then
    exit
fi
cd ~
mkdir $TARGET_DIR
mkdir $TMP_DIR
cp -r $PROJECT $TMP_DIR/CloneVersions.tmp
cd $TMP_DIR/CloneVersions.tmp
echo $PWD


rev_cnt=0
prev_rel='none'

git config diff.renameLimit 999999
for rel in $RELS
do 
    git reset --hard
    echo Check out release $rel
    git checkout -b local_$rel $rel
    rev_cnt=$((rev_cnt+1))
    ver_dir=`echo $rel | tr '/' '_'`
    ver_dir=ver$(printf %02d $rev_cnt)-$ver_dir
    echo Copy the Java files in to $ver_dir
    cp -r $TMP_DIR/CloneVersions.tmp $TARGET_DIR/$ver_dir
    find $TARGET_DIR/$ver_dir -type f ! -name *.java -delete
    echo Generate change information
    if [ $prev_rel != 'none' ]; then
        git diff --name-status local_$prev_rel local_$rel | tr '\t' ' ' | grep '.java$' | sed -E 's/^R[0-9]+/R/g'  | sed 's/ /" "/g'| sed 's/$/"/g' | sed -E 's/^A"/A/g' | sed -E 's/^D"/D/g'| sed -E 's/^M"/M/g' | sed -E 's/^R"/R/g'  > $TARGET_DIR/$ver_dir/changes
    else 
        cd $TARGET_DIR/$ver_dir
        find -type f -name *.java | cut -d '/' -f2- | sed -e 's/^/A /' |  awk -F' ' '$2{$2 = "\""$2"\""} 1' > changes
        cd $TMP_DIR/CloneVersions.tmp
    fi
    prev_rel=$rel
done
rm -rf $TMP_DIR/CloneVersions.tmp

