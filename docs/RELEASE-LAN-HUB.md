# SUMS POS Hub lokal — pemasangan dan batas versi awal

Hub ini menghubungkan waiter dan kasir melalui jaringan Wi-Fi outlet ketika internet/WAN terputus. Satu komputer kasir atau mini PC menjalankan Hub dan menyimpan database lokal. Semua perangkat operasional membuka POS dari alamat HTTPS Hub yang sama. Wi-Fi, router dan perangkat Hub harus tetap menyala.

Status implementasi: server Hub, database SQLite, integrasi POS dan endpoint cloud selesai dibangun. Uji otomatis lokal dan database sudah dijalankan. Hub belum dipasang di outlet pengguna; belum ada klaim berhasil pada jaringan fisik, iPhone/Android atau printer pengguna.

## Persiapan

- Satu perangkat Hub: Windows, macOS atau Linux dengan Node.js 24+ dan OpenSSL. Tidak ada paket npm tambahan yang perlu dipasang.
- Router memberi IP tetap atau DHCP reservation untuk Hub. Perangkat waiter dan kasir berada di jaringan yang sama; matikan client/AP isolation untuk jaringan POS. Jangan membuka port Hub ke internet.
- Akun owner, kasir dan waiter sudah tersedia. Saat persiapan awal, seluruh perangkat masih memiliki akses internet.
- Unduh dan ekstrak paket SUMS_POS_LAN_Hub.tar.gz. Jalankan perintah dari folder hasil ekstraksi.

## 1. Buat sertifikat HTTPS lokal

Contoh alamat di bawah bukan alamat outlet sebenarnya. Ganti 192.168.1.10 dengan IP LAN tetap komputer Hub.

macOS/Linux:

```sh
node hub/setup.mjs --dir "$HOME/.sums-pos-hub" --host 192.168.1.10
```

Windows PowerShell:

```powershell
node hub/setup.mjs --dir "$env:USERPROFILE\.sums-pos-hub" --host 192.168.1.10
```

Perintah membuat CA lokal dan sertifikat server berisi IP/hostname yang benar. Sertifikat yang sudah ada tidak ditimpa. Pasang dan percayai **hub-ca.crt saja** pada setiap perangkat POS menggunakan mekanisme sertifikat OS. Pada iPhone, setelah profil dipasang, aktifkan kepercayaan penuh untuk CA tersebut di pengaturan Certificate Trust. Pada Android/Windows/macOS, gunakan penyimpanan CA tepercaya yang berlaku di perangkat dan verifikasi browser menerima sertifikat tanpa peringatan. Prosesnya harus diuji pada perangkat outlet.

**hub-ca.key dan hub.key adalah private key: simpan hanya di komputer Hub.** Jangan mengirim private key ke waiter, memasukkan ke GitHub atau membagikan folder data. Hub memakai HTTPS yang dipercaya perangkat; jangan mematikan verifikasi TLS atau memakai flag browser untuk menganggap HTTP aman.

## 2. Jalankan Hub

```sh
node hub/server.mjs --dir "$HOME/.sums-pos-hub" --host 192.168.1.10
```

Pada PowerShell, ganti direktori dengan `$env:USERPROFILE\.sums-pos-hub`. Port default 7443. Jika firewall meminta akses, izinkan hanya jaringan privat outlet. Alamat contoh: `https://192.168.1.10:7443/?app=pos`.

Hub melayani aplikasi POS dan API lokal dari origin HTTPS yang sama. Perangkat tidak perlu melakukan permintaan cloud-site → private-IP lintas origin. Halaman cloud SUMS POS tetap tersedia, tetapi tidak menghubungkan waiter/kasir melalui LAN dengan sendirinya. Gunakan satu Hub per outlet; jangan mencampur kasir cloud dan kasir Hub untuk bill yang sama saat pengujian.

## 3. Aktifkan outlet dan daftarkan perangkat

1. Owner membuka alamat Hub saat internet tersedia. Untuk Back Office, gunakan query `?app=office`, login dengan akun owner yang sudah ada, lalu masuk ke Online POS jika diperlukan.
2. Di POS → Pengaturan aplikasi → **Hub lokal**, pilih **Aktifkan outlet di Hub ini**. Hub memverifikasi owner ke cloud dan mengunduh katalog, tarif, meja serta status bill dari sumber resmi.
3. Login kasir dan waiter pada alamat Hub di perangkat masing-masing, ketika masih online. Masuk ke **Hub lokal → Sambungkan perangkat**. Perangkat mendapat izin LAN selama 12 jam sejak verifikasi online; halaman/cache offline dan sesi aplikasi juga perlu sudah siap.
4. Pastikan banner menunjukkan **LAN tersambung**. Coba kirim satu pesanan waiter dan pastikan kasir melihatnya sebelum memutus WAN.
5. Tunggu antrean cloud selesai sebelum membuka shift pengujian atau mulai transaksi sungguhan.

Hub tidak menyimpan password staf, token akses/refresh Supabase atau service-role key. Hub menyimpan kunci penandatanganan khusus outlet dan hash sesi LAN. Sesi LAN dicabut saat logout jika Hub dapat dijangkau; izin offline yang tidak dapat dicabut langsung berakhir paling lambat 12 jam. Izin pengguna dan status Hub diperiksa ulang oleh cloud saat sinkronisasi.

## 4. Alur ketika internet putus

- Biarkan Wi-Fi tetap aktif dan putuskan WAN/internet router. Mode pesawat penuh mematikan Wi-Fi; jika menggunakannya, nyalakan Wi-Fi kembali.
- Waiter submit: disimpan dulu di browser, kemudian diterima dan diakui Hub. Kasir mengambil perubahan Hub setiap sekitar 2 detik selama tab terlihat. Pengiriman tidak dijamin 2 detik jika jaringan/perangkat sedang lambat.
- Status **tersimpan di perangkat** belum berarti diterima kasir. Status **diterima Hub · menunggu cloud** berarti Hub telah menyimpan pesanan, dan perangkat kasir yang tersambung dapat membacanya.
- Hub menyatukan stok lokal, pemakaian meja dan pembayaran tunai. Pesanan ganda dengan ID/isi sama tidak dicatat ulang; ID yang dipakai untuk isi berbeda ditolak. Jika dua waiter memilih meja yang sama, Hub menerima satu pesanan dan menolak yang lain untuk diperiksa.
- Kasir dapat menerima tunai untuk pesanan Hub yang dibuat waiter. Waiter tidak memiliki izin menerima pembayaran. Hub menolak pembayaran tunai kedua untuk bill yang sama.
- Data tersimpan di SQLite dengan WAL dan synchronous FULL sebelum Hub mengakui penerimaan. Restart Hub mempertahankan pesanan dan sesi LAN yang belum kedaluwarsa.
- Jika Hub atau Wi-Fi mati, pesanan baru tetap berada di browser waiter dan belum akan terlihat di kasir sampai sambungan Hub pulih. Tidak ada koneksi antarperangkat ketika jaringan lokal sendiri mati.

## 5. Ketika internet kembali

Tab kasir yang masih aktif meneruskan antrean Hub ke cloud memakai login kasir yang sah. Pengirim asli waiter serta kasir penerima uang tetap dicatat di order/payment. Hub menandatangani dokumen; cloud memverifikasi signature, membership, izin, harga, stok, tax/service dan meja. Pengakuan cloud memiliki bukti yang diverifikasi Hub sebelum status lokal berubah menjadi synced. Hilangnya respons dapat dikirim ulang tanpa order, stok atau pembayaran ganda.

Browser mengerjakan polling LAN dan sinkronisasi cloud secara terpisah, sehingga timeout cloud tidak sengaja menghentikan penerimaan pesanan lokal. Hub tidak melakukan cloud sync sendiri ketika semua tab kasir ditutup; buka kembali kasir dan sinkronkan sebelum tutup shift.

Konflik cloud tetap disimpan sebagai **review**. Harga atau stok yang berubah di luar Hub, pembayaran lain untuk bill yang sama, keanggotaan dicabut, atau Hub dinonaktifkan dapat menyebabkan penolakan. Jangan menagih ulang pembayaran fisik yang sudah diterima. Owner memeriksa catatan terlebih dahulu; **Periksa ulang antrean Hub** mencoba ulang dokumen yang sama, bukan mengubah harga atau menghapus penerimaan uang.

## Batas versi awal

- Jalur Hub mendukung pesanan baru dan pembayaran tunai. QRIS/kartu, diskon, void/refund, perubahan katalog/konfigurasi dan operasi shift tetap memerlukan internet. Belum ada cetak dapur Bluetooth/otomatis dari Hub.
- Semua perangkat harus login, mengunduh katalog dan terdaftar sebelum WAN putus. Setelah 12 jam, verifikasi online diperlukan kembali. Kehilangan sesi login browser juga membutuhkan login online.
- Setiap outlet menggunakan satu Hub. Tidak ada failover multi-Hub, discovery otomatis atau mesh antar-HP. Jika Hub mati, antrean browser bertahan tetapi belum sampai kasir.
- Semua perangkat harus selesai sinkron sebelum tutup shift. Perangkat yang sepenuhnya terputus tidak bisa diperiksa oleh Hub. Pembayaran yang baru tiba setelah shift ditutup memerlukan rekonsiliasi; versi ini tidak membuka ulang shift otomatis.
- Waktu kejadian perangkat dipertahankan, sedangkan laporan canonical yang ada menggunakan waktu penerimaan cloud. Transaksi melewati pergantian hari memerlukan pemeriksaan.
- Hub memerlukan backup dan komputer yang tetap menyala. Untuk backup sederhana, hentikan Hub dengan benar lalu salin seluruh direktori data ke media privat. Jangan menyalin database aktif tanpa mekanisme backup SQLite yang sesuai.
- Katalog dan log masih ditujukan untuk MVP. Pagination cloud dipakai, tetapi uji volume besar, pemulihan dari disk penuh, perangkat nyata dan hardening operasional lanjutan tetap diperlukan.

## Pengujian yang telah dijalankan

- Node tests: penerimaan waiter → kasir tanpa cloud, retry identik/berubah, stok/meja, pembayaran oleh kasir lain, penolakan waiter, grant kedaluwarsa, restart dengan SQLite asli, acknowledgement palsu, HTTP origin/host/auth/static root, penggabungan duplikat, urutan sinkronisasi dan reservasi lokal.
- HTTPS integration: CA dan sertifikat lokal dibuat dengan OpenSSL; server dijalankan dan client TLS memverifikasi menggunakan CA tersebut. Setup menolak menimpa private key dan HTTP LAN tidak diizinkan.
- tests/lan-hub.sql di proyek Supabase POS dengan rollback: owner-only enrollment, signature palsu, pengiriman ulang, waiter attribution, cashier attribution/shift, bukti acknowledgement, pembayaran ulang, outsider dan Hub yang dicabut.
- Pemeriksaan syntax, build dan seluruh tes aplikasi. Browser fisik/iPhone/Android/Wi-Fi serta printer belum diverifikasi.

Schema database/lan-hub.sql diterapkan sekali ke proyek POS rhebbdxgdzyvnwkvnqsh. Jangan menjalankan ulang script schema. Tabel kunci dan receipt berada di pos_private, RLS aktif tanpa policy/table grant untuk client. Entry point publik adalah security invoker dengan EXECUTE untuk anon/PUBLIC dicabut. SUMS Studio tidak dimodifikasi.

Security advisors tidak menambahkan warning baru; tabel privat tanpa client policy memang menghasilkan INFO deny-by-default. Warning pg_net pada public schema dan leaked-password protection yang sudah ada tetap terpisah dari perubahan ini.

Referensi teknis: https://nodejs.org/docs/latest-v24.x/api/sqlite.html dan https://developer.chrome.com/blog/local-network-access .
