#Thanks to Remo
#!/bin/bash
# Update and install Apache2
apt update
apt install -y apache2

# Install Google Cloud SDK
apt install -y apt-transport-https ca-certificates gnupg curl
echo "deb [signed-by=/usr/share/keyrings/cloud.google.gpg] http://packages.cloud.google.com/apt cloud-sdk main" \
  | tee -a /etc/apt/sources.list.d/google-cloud-sdk.list
curl https://packages.cloud.google.com/apt/doc/apt-key.gpg \
  | apt-key --keyring /usr/share/keyrings/cloud.google.gpg add -
apt update && apt install -y google-cloud-sdk

# Start and enable Apache2
systemctl start apache2
systemctl enable apache2

# GCP Metadata server base URL and header
METADATA_URL="http://metadata.google.internal/computeMetadata/v1"
METADATA_FLAVOR_HEADER="Metadata-Flavor: Google"

# Use curl to fetch instance metadata
local_ipv4=$(curl -H "${METADATA_FLAVOR_HEADER}" -s "${METADATA_URL}/instance/network-interfaces/0/ip")
zone=$(curl -H "${METADATA_FLAVOR_HEADER}" -s "${METADATA_URL}/instance/zone")
project_id=$(curl -H "${METADATA_FLAVOR_HEADER}" -s "${METADATA_URL}/project/project-id")
network_tags=$(curl -H "${METADATA_FLAVOR_HEADER}" -s "${METADATA_URL}/instance/tags")

#Wait until gcloud works (handle boot race conditions)
until gcloud compute instances describe "$(hostname)" --zone="$(basename $zone)" --project="$project_id" --format="value(name)" &>/dev/null; do
  echo "Waiting for gcloud API to be ready..."
  sleep 2
done

#Use a single gcloud call to get all instance info
INSTANCE_INFO=$(gcloud compute instances describe "$(hostname)" \
  --zone="$(basename $zone)" \
  --project="$project_id" \
  --format=json)

#Extract VPC and subnet info
network_url=$(echo "$INSTANCE_INFO" | grep -o '"network": *"[^"]*"' | cut -d'"' -f4)
subnet_url=$(echo "$INSTANCE_INFO" | grep -o '"subnetwork": *"[^"]*"' | cut -d'"' -f4)

network_name=$(basename "$network_url")
subnet_name=$(basename "$subnet_url")

#Get additional network info
subnet_mode=$(gcloud compute networks describe "$network_name" \
  --project="$project_id" --format="value(subnetMode)" 2>/dev/null || echo "N/A")

auto_create_subnets=$(gcloud compute networks describe "$network_name" \
  --project="$project_id" --format="value(autoCreateSubnetworks)" 2>/dev/null || echo "N/A")

routing_mode=$(gcloud compute networks describe "$network_name" \
  --project="$project_id" --format="value(routingConfig.routingMode)" 2>/dev/null || echo "N/A")

#Log variables (optional, for debugging)
echo "Zone: $zone"
echo "Project ID: $project_id"
echo "Network: $network_name"
echo "Subnet: $subnet_name"
echo "Subnet Mode: $subnet_mode"
echo "Auto Create Subnets: $auto_create_subnets"
echo "Routing Mode: $routing_mode"

# Fetch VPC and subnet info
network_name=$(gcloud compute instances describe "$(hostname)" \
  --zone="$(basename $zone)" \
  --format="get(networkInterfaces[0].network)" | awk -F'/' '{print $NF}')

subnet_name=$(gcloud compute instances describe "$(hostname)" \
  --zone="$(basename $zone)" \
  --format="get(networkInterfaces[0].subnetwork)" | awk -F'/' '{print $NF}')

subnet_mode=$(gcloud compute networks describe "$network_name" \
  --format="get(subnetMode)")

auto_create_subnets=$(gcloud compute networks describe "$network_name" \
  --format="get(autoCreateSubnetworks)")

routing_mode=$(gcloud compute networks describe "$network_name" \
  --format="get(routingConfig.routingMode)")


# Create a simple HTML page and include instance details
cat <<EOF > /var/www/html/index.html
<!DOCTYPE html>
<html>
<head>
  <title>Class 6.5</title>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <link rel="stylesheet" href="https://www.w3schools.com/w3css/4/w3.css">
  <link rel="stylesheet" href="https://fonts.googleapis.com/css?family=Raleway">
  <style>
    body,h1,h3 {font-family: "Raleway", sans-serif}
    body, html {height: 100%}
    .bgimg {
      background-image: url('https://i.imgur.com/vm3iG93.jpg');
      min-height: 100%;
      background-position: center;
      background-size: cover;
    }
    .w3-display-middle {
      background-color: rgba(0, 0, 0, 0.466);
      padding: 20px;
      border-radius: 10px;
    }
    .transparent-background {
      background-color: rgba(0, 0, 0, 0.575);
      padding: 20px;
      border-radius: 10px;
    }
    .rounded-image {
      border-radius: 25px;
    }
  </style>
</head>
<body>
  <div class="bgimg w3-display-container w3-animate-opacity w3-text-white">
    <div class="w3-display-topleft w3-padding-large w3-xlarge"></div>
    <div class="w3-display-middle w3-center">
      <video width="360" height="540" style="border-radius:10px;" controls loop autoplay muted>
          <source src="https://i.imgur.com/GPli6mO.mp4" type="video/mp4">
          Your browser does not support the video tag.
      </video>
      <hr class="w3-border-grey" style="margin:auto;width:40%;margin-top:15px;">
      <h3 class="w3-large w3-center" style="margin-top:15px;">
        <a href="https://github.com/Gwenbleidd32/startup-script-template"
           class="w3-button w3-transparent w3-border w3-border-white w3-round-large w3-text-white"
           style="margin-bottom:0px;"
           target="_blank">
          Source Code
        </a>
      </h3>
    </div>
    <div class="w3-display-bottomleft w3-padding-small transparent-background outlined-text">
      <h1>My Compute Instance Information</h1>
      <h3></h3>
      <p><b>Instance Name:</b> $(hostname -f)</p>
      <p><b>Instance Private IP Address: </b> $local_ipv4</p>
      <p><b>Zone: </b> $zone</p>
      <p><b>Project ID:</b> $project_id</p>
      <p><b>Network Tags:</b> $network_tags</p>
    </div>
    <div class="w3-display-bottomright w3-padding-small transparent-background outlined-text">
      <h1>My VPC Network Information</h1>
      <h3></h3>
      <p><b>VPC Name:</b> $network_name</p>
      <p><b>Subnet Name:</b> $subnet_name</p>
      <p><b>Subnet Mode:</b> $subnet_mode</p>
      <p><b>Auto Create Subnets:</b> $auto_create_subnets</p>
      <p><b>Routing Mode:</b> $routing_mode</p>
    </div>
  </div>
</body>
</html>
EOF
