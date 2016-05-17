cat > /etc/yum.repos.d/docker.repo << '__EOF__'
[docker]
name=Docker Repository
baseurl=https://yum.dockerproject.org/repo/main/centos/7/
enabled=1
gpgcheck=1
gpgkey=https://yum.dockerproject.org/gpg
__EOF__
 
yum -y install docker-engine wget git

mkdir -p /etc/systemd/system/docker.service.d 
 
cat > /etc/systemd/system/docker.service.d/override.conf << '__EOF__'
[Service] 
ExecStart= 
ExecStart=/usr/bin/docker daemon --storage-driver=overlay --insecure-registry 172.30.0.0/16 -H fd://
__EOF__
 
systemctl daemon-reload
systemctl enable docker
 
systemctl restart docker

mkdir /opt/openshift-origin-v1.2
chmod 755 /opt /opt/openshift-origin-v1.2
cd /opt/openshift-origin-v1.2
wget https://github.com/openshift/origin/releases/download/v1.2.0-rc1/openshift-origin-server-v1.2.0-rc1-061e6d4-linux-64bit.tar.gz
tar -zxvf openshift-origin-server-*.tar.gz --strip-components 1
rm -f openshift-origin-server-*.tar.gz

cat > /etc/profile.d/openshift.sh << '__EOF__'
export OPENSHIFT=/opt/openshift-origin-v1.2
export OPENSHIFT_VERSION=v1.2.0-rc1
export PATH=$OPENSHIFT:$PATH
export KUBECONFIG=$OPENSHIFT/openshift.local.config/master/admin.kubeconfig
export CURL_CA_BUNDLE=$OPENSHIFT/openshift.local.config/master/ca.crt
__EOF__

chmod 755 /etc/profile.d/openshift.sh
. /etc/profile.d/openshift.sh

docker pull openshift/origin-pod:$OPENSHIFT_VERSION
docker pull openshift/origin-sti-builder:$OPENSHIFT_VERSION
docker pull openshift/origin-docker-builder:$OPENSHIFT_VERSION
docker pull openshift/origin-deployer:$OPENSHIFT_VERSION
docker pull openshift/origin-docker-registry:$OPENSHIFT_VERSION
docker pull openshift/origin-haproxy-router:$OPENSHIFT_VERSION

./openshift start --write-config=openshift.local.config
chmod +r $OPENSHIFT/openshift.local.config/master/admin.kubeconfig
chmod +r $OPENSHIFT/openshift.local.config/master/openshift-registry.kubeconfig
chmod +r $OPENSHIFT/openshift.local.config/master/openshift-router.kubeconfig

sed -i 's/router.default.svc.cluster.local/apps.acmeaws.com/' $OPENSHIFT/openshift.local.config/master/master-config.yaml

firewall-cmd --permanent --zone=public --add-port=80/tcp
firewall-cmd --permanent --zone=public --add-port=443/tcp
firewall-cmd --permanent --zone=public --add-port=8443/tcp
firewall-cmd --reload

cat > /etc/systemd/system/openshift-origin.service << '__EOF__'
[Unit]
Description=Origin Master Service
After=docker.service
Requires=docker.service
 
[Service]
Restart=always
RestartSec=10s
ExecStart=/opt/openshift-origin-v1.2/openshift start
WorkingDirectory=/opt/openshift-origin-v1.2
 
[Install]
WantedBy=multi-user.target
__EOF__
 
systemctl daemon-reload
systemctl enable openshift-origin
systemctl start openshift-origin

oc login -u system:admin -n default
mkdir /opt/openshift-registry
chcon -Rt svirt_sandbox_file_t /opt/openshift-registry
chown 1001.root /opt/openshift-registry
oadm policy add-scc-to-user privileged -z registry 
oadm registry --service-account=registry --mount-host=/opt/openshift-registry


oadm policy add-scc-to-user hostnetwork -z router
oadm router router --replicas=1 --service-account=router

cd ~
git clone https://github.com/openshift/openshift-ansible.git
cd openshift-ansible/roles/openshift_examples/files/examples/latest/
for f in image-streams/image-streams-centos7.json; do cat $f | oc create -n openshift -f -; done
for f in db-templates/*.json; do cat $f | oc create -n openshift -f -; done
for f in quickstart-templates/*.json; do cat $f | oc create -n openshift -f -; done
