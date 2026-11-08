#!/bin/bash
# =====================================================================
#  GSP761 - Developing a REST API with Go and Cloud Run
#  Credit : Jutapen
#  Lisensi: MIT
# =====================================================================
set -e

# ----- Warna -----
if [ -t 1 ]; then
  RED=$'\e[1;31m'; GREEN=$'\e[1;32m'; YELLOW=$'\e[1;33m'
  BLUE=$'\e[1;34m'; CYAN=$'\e[1;36m'; RESET=$'\e[0m'
else
  RED=""; GREEN=""; YELLOW=""; BLUE=""; CYAN=""; RESET=""
fi
info() { echo -e "${CYAN}[INFO]${RESET} $*"; }
ok()   { echo -e "${GREEN}[ OK ]${RESET} $*"; }
warn() { echo -e "${YELLOW}[WARN]${RESET} $*"; }
step() { echo -e "\n${BLUE}==== $* ====${RESET}"; }
trap 'echo -e "${RED}[ERROR] Script berhenti di baris $LINENO${RESET}"' ERR

echo -e "${CYAN}"
echo "  GSP761 - Developing a REST API with Go and Cloud Run"
echo "  Credit: Jutapen"
echo -e "${RESET}"

# ----- Input otomatis dari environment -----
PROJECT_ID="${GOOGLE_CLOUD_PROJECT:-$(gcloud config get-value project 2>/dev/null)}"
if [ -z "$PROJECT_ID" ]; then
  echo -e "${RED}Project ID tidak terdeteksi. Jalankan di Cloud Shell lab.${RESET}"; exit 1
fi
export GOOGLE_CLOUD_PROJECT="$PROJECT_ID"

REGION="${REGION:-$(gcloud config get-value compute/region 2>/dev/null || true)}"
if [ -z "$REGION" ]; then
  printf "%sMasukkan REGION dari panel Lab (contoh: us-central1): %s" "$YELLOW" "$RESET"
  read -r REGION </dev/tty
fi
info "Project: $PROJECT_ID | Region: $REGION"

REPO="$REGION-docker.pkg.dev/$PROJECT_ID/my-repo"

pause() {
  echo
  echo -e "${YELLOW}>>> Klik 'Check my progress' untuk: ${GREEN}$1${RESET}"
  printf "%sTekan ENTER setelah progress terverifikasi... %s" "$YELLOW" "$RESET"
  read -r _ </dev/tty
}

deploy() {
  local img="$REPO/rest-api:$1" cur
  cur=$(gcloud run services describe rest-api --region "$REGION" \
        --format='value(spec.template.spec.containers[0].image)' 2>/dev/null || true)
  if [ "$cur" = "$img" ]; then
    warn "Service sudah memakai $img, lewati deploy."
  else
    gcloud run deploy rest-api \
      --image "$img" \
      --region "$REGION" \
      --allow-unauthenticated \
      --max-instances=2
  fi
}

build_image() {
  local img="$REPO/rest-api:$1"
  if gcloud artifacts docker images describe "$img" >/dev/null 2>&1; then
    warn "Image $img sudah ada, lewati build."
  else
    gcloud builds submit --tag "$img"
  fi
}

# ===== Task 2: Developing the REST API =====
step "Task 2: Developing the REST API"
gcloud config set project "$PROJECT_ID"
cd ~
[ -d pet-theory ] || git clone https://github.com/rosera/pet-theory.git
cd ~/pet-theory/lab08

cat > main.go <<'EOF'
package main

import (
  "fmt"
  "log"
  "net/http"
  "os"
)

func main() {
  port := os.Getenv("PORT")
  if port == "" {
      port = "8080"
  }
  http.HandleFunc("/v1/", func(w http.ResponseWriter, r *http.Request) {
      fmt.Fprintf(w, "{status: 'running'}")
  })
  log.Println("Pets REST API listening on port", port)
  if err := http.ListenAndServe(":"+port, nil); err != nil {
      log.Fatalf("Error launching Pets REST API server: %v", err)
  }
}
EOF

cat > Dockerfile <<'EOF'
FROM gcr.io/distroless/base-debian12
WORKDIR /usr/src/app
COPY server .
CMD [ "/usr/src/app/server" ]
EOF

go build -o server
ls -la

if ! gcloud artifacts repositories describe my-repo --location="$REGION" >/dev/null 2>&1; then
  gcloud artifacts repositories create my-repo \
    --repository-format=docker \
    --location="$REGION" \
    --description="Docker repository for REST API"
else
  warn "Repository my-repo sudah ada."
fi

build_image 0.1
pause "Build an image with Cloud Build"

deploy 0.1
pause "REST API service deployed"

SERVICE_URL=$(gcloud run services describe rest-api --region "$REGION" --format='value(status.url)')
info "Tes /v1/ :"
curl -s "$SERVICE_URL/v1/"; echo

# ===== Task 3: Import test customer data =====
step "Task 3: Import test customer data"
if gcloud firestore databases describe --database='(default)' >/dev/null 2>&1; then
  warn "Database Firestore sudah ada."
else
  gcloud firestore databases create --database='(default)' \
    --location="$REGION" --edition=standard || {
    warn "Pembuatan via CLI gagal. Buat manual di Console:"
    echo "  Navigation menu > Databases > Firestore > Create a Firestore database"
    echo "  Standard Edition, Security rules: Open, Location type: Region, region: $REGION"
    printf "%sTekan ENTER setelah database selesai dibuat... %s" "$YELLOW" "$RESET"
    read -r _ </dev/tty
  }
fi
pause "Firestore database created"

if ! gcloud storage buckets describe "gs://$PROJECT_ID-customer" >/dev/null 2>&1; then
  gcloud storage buckets create "gs://$PROJECT_ID-customer" \
    --default-storage-class=standard --location="$REGION"
fi
gcloud storage cp -r gs://spls/gsp645/2019-10-06T20:10:37_43617 "gs://$PROJECT_ID-customer"
gcloud beta firestore import "gs://$PROJECT_ID-customer/2019-10-06T20:10:37_43617/"
ok "Data pelanggan terimpor."

# ===== Task 4: Connect REST API to Firestore =====
step "Task 4: Connect REST API to Firestore"
cat > main.go <<'EOF'
package main

import (
	"context"
	"encoding/json"
	"fmt"
	"log"
	"net/http"
	"os"

	"cloud.google.com/go/firestore"
	"github.com/gorilla/handlers"
	"github.com/gorilla/mux"
	"google.golang.org/api/iterator"
)

var client *firestore.Client

func main() {
	var err error
	ctx := context.Background()
	client, err = firestore.NewClient(ctx, "PROJECT_ID_PLACEHOLDER")
	if err != nil {
		log.Fatalf("Error initializing Cloud Firestore client: %v", err)
	}

	port := os.Getenv("PORT")
	if port == "" {
		port = "8080"
	}

	r := mux.NewRouter()
	r.HandleFunc("/v1/", rootHandler)
	r.HandleFunc("/v1/customer/{id}", customerHandler)

	log.Println("Pets REST API listening on port", port)
	cors := handlers.CORS(
		handlers.AllowedHeaders([]string{"X-Requested-With", "Authorization", "Origin"}),
		handlers.AllowedOrigins([]string{"https://storage.googleapis.com"}),
		handlers.AllowedMethods([]string{"GET", "HEAD", "POST", "OPTIONS", "PATCH", "CONNECT"}),
	)

	if err := http.ListenAndServe(":"+port, cors(r)); err != nil {
		log.Fatalf("Error launching Pets REST API server: %v", err)
	}
}

func rootHandler(w http.ResponseWriter, r *http.Request) {
  fmt.Fprintf(w, "{status: 'running'}")
}

func customerHandler(w http.ResponseWriter, r *http.Request) {
  id := mux.Vars(r)["id"]
  ctx := context.Background()
  customer, err := getCustomer(ctx, id)
  if err != nil {
    w.WriteHeader(http.StatusInternalServerError)
    fmt.Fprintf(w, `{"status": "fail", "data": '%s'}`, err)
    return
  }
  if customer == nil {
    w.WriteHeader(http.StatusNotFound)
    msg := fmt.Sprintf("`Customer \"%s\" not found`", id)
    fmt.Fprintf(w, fmt.Sprintf(`{"status": "fail", "data": {"title": %s}}`, msg))
    return
  }
  amount, err := getAmounts(ctx, customer)
  if err != nil {
    w.WriteHeader(http.StatusInternalServerError)
    fmt.Fprintf(w, `{"status": "fail", "data": "Unable to fetch amounts: %s"}`, err)
    return
  }
  data, err := json.Marshal(amount)
  if err != nil {
    w.WriteHeader(http.StatusInternalServerError)
    fmt.Fprintf(w, `{"status": "fail", "data": "Unable to fetch amounts: %s"}`, err)
    return
  }
  fmt.Fprintf(w, fmt.Sprintf(`{"status": "success", "data": %s}`, data))
}

type Customer struct {
  Email string `firestore:"email"`
  ID    string `firestore:"id"`
  Name  string `firestore:"name"`
  Phone string `firestore:"phone"`
}

func getCustomer(ctx context.Context, id string) (*Customer, error) {
  query := client.Collection("customers").Where("id", "==", id)
  iter := query.Documents(ctx)

  var c Customer
  for {
    doc, err := iter.Next()
    if err == iterator.Done {
	break
    }
    if err != nil {
	return nil, err
    }
    err = doc.DataTo(&c)
    if err != nil {
	return nil, err
    }
  }
  return &c, nil
}

func getAmounts(ctx context.Context, c *Customer) (map[string]int64, error) {
  if c == nil {
    return map[string]int64{}, fmt.Errorf("Customer should be non-nil: %v", c)
  }
  result := map[string]int64{
    "proposed": 0,
    "approved": 0,
    "rejected": 0,
  }
  query := client.Collection(fmt.Sprintf("customers/%s/treatments", c.Email))
  if query == nil {
    return map[string]int64{}, fmt.Errorf("Query is nil: %v", c)
  }
  iter := query.Documents(ctx)
  for {
    doc, err := iter.Next()
    if err == iterator.Done {
	break
    }
    if err != nil {
	return nil, err
    }
    treatment := doc.Data()
    result[treatment["status"].(string)] += treatment["cost"].(int64)
  }
  return result, nil
}
EOF
sed -i "s/PROJECT_ID_PLACEHOLDER/$PROJECT_ID/" main.go

# ===== Task 7: Deploy revision 0.2 =====
step "Task 7: Deploying a new revision"
go build -o server
build_image 0.2
pause "Build image revision 0.2"

deploy 0.2

# ===== Verifikasi =====
step "Verifikasi"
SERVICE_URL=$(gcloud run services describe rest-api --region "$REGION" --format='value(status.url)')
for p in /v1/ /v1/customer/22530 /v1/customer/34216 /v1/customer/70156 /v1/customer/12345; do
  echo -e "${CYAN}== $p${RESET}"; curl -s "$SERVICE_URL$p"; echo
done
ok "Selesai. Service URL: $SERVICE_URL"
echo -e "${CYAN}Credit: Jutapen${RESET}"
