#!/bin/bash
set -o pipefail

MODIFIER='' # -dev for development, -test for test, blank for production
INSTALL_DIRECTORY='/opt/fnet'
LOGS_DIRECTORY='/var/log/fnet/gemini'
UNPACKAGED_AGENT_DIR='gemini'
LOCK_DIRECTORY=$INSTALL_DIRECTORY/$UNPACKAGED_AGENT_DIR
GEMINI_DIRECTORY='\/opt\/fnet\/gemini'

GUID=$1

if [ -z "$GUID" ]; then
  echo "A GUID is required to run the script"
  exit -1
fi

# First thing we have to do is check what OS we are on
if [ "$(uname -s)" == 'FreeBSD' ]; then

  OS='FreeBSD'
  AGENT_PACKAGE=GeminiInstall.FREEBSD.latest$MODIFIER.zip

elif [ -f "/etc/redhat-release" ]; then

  RHV=$(egrep -o 'Fedora|CentOS|Red Hat' /etc/redhat-release)
  case $RHV in
    Fedora)  OS='fedora'
             AGENT_PACKAGE=GeminiInstall.FEDORA.latest$MODIFIER.zip
             ;;
    CentOS)  OS='centos'
             AGENT_PACKAGE=GeminiInstall.RHEL.latest$MODIFIER.zip
             ;;
 'Red Hat')  OS='redhat'
             AGENT_PACKAGE=GeminiInstall.RHEL.latest$MODIFIER.zip
             ;;
  esac

elif [ -f "/etc/system-release" ]; then
  OS='amazon'
  REGION=`/opt/aws/bin/ec2-metadata -z | grep -Po "(us|sa|eu|ap)-(north|south)?(east|west)?-[0-9]"`
  AGENT_PACKAGE=GeminiInstall.AMI.latest$MODIFIER.$REGION.zip
elif [ -f "/etc/debian_version" ]; then
  OS='debian'
  AGENT_PACKAGE=GeminiInstall.DEBIAN.latest$MODIFIER.zip
elif [ -f "/etc/arch-release" ]; then
  OS='arch'
  AGENT_PACKAGE=GeminiInstall.ARCH.latest$MODIFIER.zip
elif [ -f "/etc/SuSE-release" ]; then
  OS='suse'
  AGENT_PACKAGE=GeminiInstall.SUSE.latest$MODIFIER.zip
else
  OS='Unknown operating system'
fi

WEBSITE_URL=https://s3.amazonaws.com/cold-thunder-artifacts/$AGENT_PACKAGE

echo "$OS detected, downloading $WEBSITE_URL"

if [ "$OS" == "Unknown operating system" ]; then
  echo "Installation cannot proceed."
  echo "Please contact the Fluke Networks support team."
  exit -1
fi

# Next download the agent package
echo "Attempting to download agent package from "$WEBSITE_URL

curl -O $WEBSITE_URL

if [ $? -eq 0 ]; then
  echo 'Agent download complete'
else
  echo 'Agent package download failed, please try again later'
  exit -1
fi

# Delete any previous packages
if [ -d "$UNPACKAGED_AGENT_DIR" ]; then
  sudo rm -rf $UNPACKAGED_AGENT_DIR
fi

# Now upzip it
unzip $AGENT_PACKAGE -d $UNPACKAGED_AGENT_DIR

# Test for existence of the executable
if [ ! -f $UNPACKAGED_AGENT_DIR/gemini ]; then
  echo "Problem with download package.  Please contact the Fluke Networks support team."
  exit -1
fi

# Run any separate actions
if [ -f $UNPACKAGED_AGENT_DIR/runme ]; then
  chmod +x $UNPACKAGED_AGENT_DIR/runme
  $UNPACKAGED_AGENT_DIR/runme
fi

# Replace the guid place holder with the supplied GUID in the gemini script
sed -i "s/ORG_GUID/$GUID/g" $UNPACKAGED_AGENT_DIR/gemini.ini
sed -i "s/INSTALL_DIR/$GEMINI_DIRECTORY/g" $UNPACKAGED_AGENT_DIR/gemini.ini
sed -i "s/INSTALL_DIR/$GEMINI_DIRECTORY/g" $UNPACKAGED_AGENT_DIR/gemini_log.properties

# now move the sanitized agent directory into the install directory
if [ ! -d "$INSTALL_DIRECTORY" ]; then
  echo 'Setting up agent destination'
  sudo mkdir -p $INSTALL_DIRECTORY
fi

if [ -d "$INSTALL_DIRECTORY/$UNPACKAGED_AGENT_DIR" ]; then
  echo 'Cleaning up prior installation'
  sudo /etc/init.d/fnet_gemini stop
  sudo rm -rf $INSTALL_DIRECTORY/$UNPACKAGED_AGENT_DIR
fi

sudo chmod ug+x $UNPACKAGED_AGENT_DIR/gemini
sudo chmod ug+x $UNPACKAGED_AGENT_DIR/gemini_service
sudo chmod ug+x $UNPACKAGED_AGENT_DIR/gemini_monitor
sudo chmod ug+x $UNPACKAGED_AGENT_DIR/*.sh
sudo mv $UNPACKAGED_AGENT_DIR/gemini_service /etc/init.d/fnet_gemini

sudo mv $UNPACKAGED_AGENT_DIR $INSTALL_DIRECTORY

if [ "$OS" == "debian" ]; then
  sudo update-rc.d -f fnet_gemini remove
  sudo update-rc.d fnet_gemini defaults
else
  sudo /sbin/chkconfig --level 35 fnet_gemini on
fi

sudo /etc/init.d/fnet_gemini start

if [ $? -eq 0 ]; then
  rm -f $AGENT_PACKAGE
  echo 'Agent installation complete'
else
  echo 'Agent installation failed'
  exit -1
fi
