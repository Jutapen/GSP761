# GSP761 - Developing a REST API with Go and Cloud Run

> **Credit: Jutapen**

Script bash otomatis untuk lab Google Cloud **GSP761: Developing a REST API with Go and Cloud Run**.
Script membangun REST API Go, mengimpor data uji ke Firestore, menghubungkannya, lalu men-deploy ke Cloud Run,
dengan jeda di setiap tombol **Check my progress**.

## Cara pakai (satu baris)

Buka Cloud Shell di lab, lalu jalankan:

```bash
curl -fsSL https://raw.githubusercontent.com/Jutapen/GSP761/main/gsp761.sh | bash
```

- Project ID diambil otomatis dari environment.
- Region diambil dari konfigurasi gcloud. Jika kosong, kamu akan ditanya (isi sesuai panel "Lab setup and access").
- Script berhenti 4 kali. Klik **Check my progress** di halaman lab, lalu tekan **ENTER**:
  1. Build an image with Cloud Build
  2. REST API service deployed
  3. Firestore database created
  4. Build image revision 0.2

Opsi: `REGION=nama-region bash gsp761.sh` agar tidak ditanya.

## Langkah manual (GUI)

Jika bagian tertentu gagal lewat CLI:

1. **Firestore**: Navigation menu > Databases > Firestore > *Create a Firestore database* >
   **Standard Edition**, Security rules **Open**, Location type **Region**, pilih region lab > *Create Database*.
2. **Cek image**: Navigation menu > View All Products > Artifact Registry > repositori `my-repo` > pastikan `rest-api` ada
   (klik Refresh jika belum muncul).
3. **Cek service**: Navigation menu > Cloud Run > `rest-api` > buka URL, tambahkan `/v1/`
   lalu `/v1/customer/22530`.
4. **Cek data**: Firestore > koleksi `customers` harus berisi data pelanggan.
5. **Pop quiz (Task 6)** dijawab langsung di halaman lab.

## Yang normal terjadi

- `/v1/` menampilkan `{status: 'running'}` (bukan JSON valid, memang begitu kodenya).
- `/v1/customer/22530` menampilkan `{"status": "success", "data": {"proposed":1602,"approved":585,"rejected":489}}`.
- `/v1/customer/70156`: semua nilai 0.
- `/v1/customer/12345`: respons error (misalnya "Query is nil"), sesuai instruksi lab.
- Menjalankan ulang script aman: repo, bucket, database, image, dan service yang sudah ada dilewati.
  Import Firestore dijalankan ulang dan hanya menimpa dokumen yang sama.
- Peringatan `go vet` pada `fmt.Fprintf(w, fmt.Sprintf(...))` tidak berpengaruh pada build.

## Disclaimer

Proyek ini untuk tujuan belajar dan **tidak berafiliasi dengan Google**. Gunakan hanya pada akun
student sementara yang disediakan lab, bukan akun Google Cloud pribadi. Pahami isi script sebelum
menjalankannya (`curl | bash` mengeksekusi kode dari internet). Tanggung jawab penggunaan ada pada
kamu; ikuti aturan platform lab dan institusimu. Perangkat lunak disediakan "apa adanya" tanpa jaminan.

## Lisensi

MIT. Lihat [LICENSE](LICENSE). Credit: Jutapen.
