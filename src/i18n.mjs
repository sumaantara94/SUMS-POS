let language='en';try{language=localStorage.getItem('sums-pos-language')==='id'?'id':'en'}catch{}
export const getLanguage=()=>language;
export const locale=()=>language==='en'?'en-GB':'id-ID';
export function setLanguage(value){language=value==='id'?'id':'en';try{localStorage.setItem('sums-pos-language',language)}catch{}if(typeof document!=='undefined')document.documentElement.lang=language}
const rows=`
Pilih meja|Select a table
Edit reservasi|Edit reservation
Batalkan reservasi|Cancel reservation
Batalkan reservasi?|Cancel reservation?
Meja akan tersedia kembali.|The table will become available again.
Waiter dapat memilih meja reservasi untuk tamu yang sudah datang.|Waiters can select reserved tables when guests arrive.
Reservasi telah berubah. Muat ulang dan pilih meja kembali|Reservation has changed. Refresh and select the table again
Reservasi tidak ditemukan|Reservation not found

Cari produk|Search products
Tutup basket|Close basket
Basket pesanan|Order basket
Filter grup kategori|Filter category group
Periode laporan|Report period
Grup kategori laporan|Report category group
Grafik penjualan tujuh hari|Seven-day sales chart
Pilih varian|Choose variant
Cetak pesanan per section|Print order by section
Pilih cetak struk / section|Choose receipt / section printing
Pilih printer di dialog|Choose a printer in the dialog
Foto siap disimpan|Photo ready to save
Isi data produk dengan benar|Enter valid product details
Kategori belum tercatat|Category not recorded
Mengoptimalkan foto…|Optimizing photo…
Menyimpan…|Saving…
Nilai bill IDR|Bill value (IDR)
Owner membuat akun staf dengan nama, username, password, dan peran.|The owner creates staff accounts with a name, username, password and role.
Setiap section perlu nama dan kategori|Each section needs a name and category
TAGIHAN BELUM LUNAS|UNPAID BILL
STRUK PEMBAYARAN|PAYMENT RECEIPT
Tidak ada item untuk section ini|No items for this section
Tunggu foto selesai diproses|Wait for the photo to finish processing
Jumlah tidak valid|Invalid quantity
Pilih produk terlebih dahulu|Select a product first
Produk tidak tersedia|Product unavailable
Tambah bisnis|Add business
Nama bisnis wajib diisi|Business name is required
Akses ditolak|Access denied
Identitas bisnis tersimpan|Business identity saved
Akun staf dibuat. Staf dapat login menggunakan username.|Staff account created. The staff member can log in with their username.
Pengaturan printer tersimpan|Printer settings saved
contoh: aruna.kasir01|e.g. aruna.cashier01

Pesanan|Orders
Produk & inventory|Products & inventory
Laporan penjualan|Sales reports
Pengaturan bisnis|Business settings
Meja & reservasi|Tables & reservations
Pengaturan|Settings
Pengaturan aplikasi|App settings
Produk|Products
Meja|Tables
Bahasa|Language
Bahasa aplikasi|App language
Muat ulang|Refresh
Koneksi|Connection
Akun|Account
Tunai|Cash
Tutup|Close
Pilih bisnis|Select a business
Area meja|Table area
Kosong = pertahankan PIN saat ini|Leave empty to keep the current PIN
Nomor referensi, bukan nomor kartu|Transaction reference, not the card number
Geser meja di dalam area layout|Move the table within the layout
Pesanan tidak ada pada daftar yang dimuat|Order is not in the loaded list
Jumlah meja harus 0–144|Table count must be between 0 and 144
Periksa rentang meja dan kapasitas 1–100|Check the table range and capacity (1–100)
Klik meja untuk mengubah nama, kapasitas atau ketersediaan.|Click a table to change its name, capacity or availability.
Geser meja ke tempat kosong. Taruh di atas meja lain untuk menukar posisi.|Drag a table to an empty position, or onto another table to swap positions.
Printer|Printer
Pasang aplikasi|Install app
Install sekarang|Install now
Keluar|Log out
Buka Back Office|Open Back Office
Buka POS Online ↗|Open Online POS ↗
Business overview|Business overview
Lihat aktivitas bisnis Anda dalam satu pandangan.|Your business activity at a glance.
Pesanan lebih rapi. Pelayanan lebih lancar.|Organized orders. Smoother service.
Pantau pesanan yang menunggu pembayaran.|Manage orders awaiting payment.
Kelola katalog dan ketersediaan produk.|Manage your catalogue and product availability.
Angka yang membantu Anda mengambil keputusan.|Numbers to help you make decisions.
Workspace yang mengikuti identitas bisnis Anda.|A workspace that reflects your business.
Ketersediaan meja, open bill dan reservasi.|Table availability, open bills and reservations.
Operasional rapi, bisnis terkendali.|Organized operations. Your business in control.
Penerimaan hari ini|Today's collections
Rata-rata tagihan|Average bill
Berdasarkan transaksi hari ini|Based on today's transactions
Pesanan aktif|Open orders
Menunggu pembayaran|Awaiting payment
Stok perlu perhatian|Stock needs attention
Produk dengan stok ≤ 15|Products with stock ≤ 15
Penerimaan 7 hari|7-day collections
Transaksi lunas · IDR|Paid transactions · IDR
Siapkan stok sebelum jam ramai.|Prepare stock before the rush.
Stok produk masih cukup.|Stock levels are healthy.
Transaksi terbaru|Recent transactions
Lihat laporan ↗|View reports ↗
Waiter belum aktif|Waiter mode is disabled
Owner perlu mengaktifkan mode Restaurant dan waiter di Back Office.|The owner must enable Restaurant and Waiter mode in Back Office.
1. Pilih meja|1. Select a table
Meja terisi tidak dapat dipilih untuk pesanan baru.|Occupied tables cannot be selected for a new order.
Pesanan takeaway|Takeaway order
2. Nama tamu|2. Guest name
Nama tamu|Guest name
Lanjut pilih menu →|Continue to products →
Pilih meja lain|Choose another table
Ubah meja / tamu|Change table / guest
Cari produk...|Search products...
Semua kategori|All categories
Produk tidak ditemukan.|No products found.
Periksa jumlah dan catatan sebelum submit.|Review quantities and notes before submitting.
Keranjang masih kosong|Your basket is empty
Jenis pesanan|Order type
Subtotal menu|Menu subtotal
Total biaya|Total amount
Catatan item|Item note
＋ Catatan item|＋ Item note
Edit catatan|Edit note
Instruksi untuk Kitchen / Bar|Kitchen / Bar instructions
Simpan catatan|Save note
PESANAN|ORDER
WAKTU|TIME
REFERENSI|REFERENCE
TOTAL|TOTAL
STATUS|STATUS
AKSI|ACTIONS
Lunas|Paid
Aktif|Active
Batal|Cancelled
Bayar|Pay
Batalkan|Cancel
Detail / cetak|Details / print
Belum ada pesanan.|No orders yet.
Semua grup|All groups
Semua grup kategori|All category groups
Kelola kategori|Manage categories
+ Tambah produk|+ Add product
GRUP KATEGORI|CATEGORY GROUP
HARGA JUAL|SELLING PRICE
HARGA BELI / HPP|PURCHASE COST / COGS
STOK|STOCK
Belum diisi|Not set
Edit / stok|Edit / stock
Harian|Today
7 hari terakhir|Last 7 days
30 hari terakhir|Last 30 days
Penjualan neto tercatat|Recorded net sales
Periode dan kategori terpilih|Selected period and category
Transaksi|Transactions
Transaksi lunas|Paid transactions
HPP transaksi|Transaction COGS
Laba kotor|Gross profit
Belum lengkap|Incomplete
Harga pokok saat pesanan dibuat|Cost recorded when the order was created
Penjualan neto − HPP, sebelum biaya operasional|Net sales − COGS, before operating expenses
Performa grup kategori|Category performance
KATEGORI|CATEGORY
ITEM TERJUAL|ITEMS SOLD
PENJUALAN NETO|NET SALES
LABA KOTOR|GROSS PROFIT
HPP|COGS
Identitas bisnis|Business identity
Tampilan workspace mengikuti bisnis Anda.|Personalize your business workspace.
Nama bisnis|Business name
Jenis bisnis|Business type
Warna brand|Brand colour
Simpan identitas|Save identity
Workspace bisnis|Business workspace
Tambahkan bisnis dengan katalog dan transaksi sendiri.|Add a business with its own catalogue and transactions.
+ Tambah workspace · Upgrade|+ Add workspace · Upgrade
Workspace tambahan membutuhkan upgrade plan. Flow pembayaran menyusul.|Additional workspaces require an upgraded plan. Billing will follow.
Simulasi hak akses|Access roles
Seluruh modul|All modules
Pesanan & pembayaran|Orders & payments
Input & cetak pesanan|Order entry & section printing
Logo & pengaturan cetak|Logo & printing settings
Kelola akses staf|Manage staff access
Foto produk|Product photo
Hapus foto|Remove photo
Foto dioptimalkan otomatis untuk POS.|Photos are optimized automatically for POS.
Nama|Name
Kategori|Category
Pilih kategori|Select a category
Buat kategori melalui Kelola kategori.|Create categories in Manage categories.
Harga IDR|Price (IDR)
Harga beli / HPP per unit (IDR)|Purchase cost / unit COGS (IDR)
Stok tersedia|Available stock
Status|Status
Nonaktif|Inactive
Simpan produk|Save product
Kelola varian & harga|Manage variants & prices
Simpan produk dahulu untuk menambahkan varian.|Save the product before adding variants.
Produk baru|New product
Edit produk|Edit product
Upgrade workspace|Upgrade workspace
Penambahan workspace akan tersedia melalui upgrade plan. Pembayaran belum diaktifkan.|Additional workspaces will be available with an upgraded plan. Billing is not enabled yet.
Alasan pembatalan|Cancellation reason
Batalkan pesanan|Cancel order
Stok dikembalikan dan meja tersedia kembali setelah berhasil.|Stock is restored and the table becomes available after cancellation.
PIN pembatalan|Cancellation PIN
Gunakan dialog print browser. Bluetooth langsung belum terintegrasi.|Use the system print dialog. Direct Bluetooth is not integrated yet.
Kelola staf|Manage staff
Belum ada akun staf dengan username.|No staff username accounts yet.
Tambah staf|Add staff
Nama lengkap|Full name
Akses|Access
Kasir · pesanan & pembayaran|Cashier · orders & payments
Waiter · pesanan & cetak section|Waiter · orders & section printing
Buat akun staf|Create staff account
Username unik di seluruh SUMS POS. Staf langsung login tanpa email konfirmasi.|Usernames are unique across SUMS POS. Staff can log in without email confirmation.
Kategori produk|Product categories
Kategori tersimpan untuk produk sekarang dan berikutnya.|Categories are saved for current and future products.
+ Kategori baru|+ New category
Edit kategori|Edit category
Kategori baru|New category
Nama kategori|Category name
Simpan kategori|Save category
Ukuran kertas|Paper width
Nama printer / perangkat|Printer / device name
Simpan pengaturan|Save settings
Pengaturan perangkat/browser ini. Printer fisik dipilih di dialog cetak sistem.|Settings for this device/browser. Select the physical printer in the system print dialog.
Belum menghubungkan Bluetooth secara langsung atau mengganti printer OS otomatis.|Direct Bluetooth and automatic system printer selection are not supported yet.
Logo & cetak bisnis|Business logo & printing
Logo PNG / JPEG / WebP · maksimal 200 KB|PNG / JPEG / WebP logo · maximum 200 KB
Hapus logo|Remove logo
Lebar struk default|Default receipt width
Section persiapan|Preparation sections
Kasir mencetak struk. Waiter mencetak item per kategori ke section Kitchen/Bar yang dipilih.|Cashiers print receipts. Waiters print category items to the selected Kitchen/Bar section.
Nama printer|Printer name
Ukuran|Width
Hapus section|Remove section
+ Section printer|+ Printer section
Simpan logo & section|Save logo & sections
Pilih dokumen cetak|Choose a print document
Struk kasir · seluruh pembelanjaan|Cashier receipt · entire bill
Pesanan waiter|Waiter order
Cetak section|Print section
Owner perlu mengatur section dan kategori di Pengaturan bisnis → Logo & cetak.|The owner must configure sections and categories in Business settings → Logo & printing.
Pilih printer yang sesuai pada dialog cetak untuk setiap section.|Choose the correct printer for each section in the system print dialog.
Terima kasih|Thank you
Mulai dari pesanan.|Start with an order.
Tumbuh bersama bisnis.|Grow with your business.
Produk, pelayanan, pembayaran, dan angka bisnis Anda dalam satu workspace.|Products, service, payments and business insights in one workspace.
Buat akun Anda|Create your account
Selamat datang kembali|Welcome back
Daftar, lalu siapkan identitas bisnis Anda.|Sign up, then set up your business identity.
Masuk untuk membuka bisnis dan operasional Anda.|Log in to manage your business and operations.
Email owner|Owner email
Email owner / Username staf|Owner email / Staff username
Daftar akun|Sign up
Masuk|Log in
Sudah punya akun? Masuk|Already have an account? Log in
Belum punya akun? Daftar|Don't have an account? Sign up
Lihat demo tanpa login|View demo without logging in
Menghubungkan...|Connecting...
Cek email untuk konfirmasi akun, lalu kembali dan masuk.|Check your email to confirm your account, then return to log in.
Workspace untuk|A workspace for
bisnis Anda.|your business.
Mulai dengan identitas bisnis. Katalog dapat ditambahkan setelah workspace dibuat.|Start with your business identity. Add your catalogue after creating the workspace.
Siapkan bisnis Anda|Set up your business
Buat workspace|Create workspace
Staf yang sudah diberi akses dapat memuat ulang workspace.|Staff with access can refresh their workspace.
Muat ulang akses|Refresh access
Setiap varian memiliki harga dan stok sendiri. HPP mengikuti produk utama.|Each variant has its own price and stock. COGS follows the main product.
Nama varian|Variant name
Harga jual|Selling price
Stok varian|Variant stock
+ Varian|+ Variant
Simpan varian & harga|Save variants & prices
Tambah|Add
Laporan void / cancel|Void / cancellation report
WAKTU BATAL|CANCELLED AT
PEMBUAT|CREATED BY
DIBATALKAN OLEH|CANCELLED BY
ALASAN|REASON
NILAI BILL|BILL VALUE
Tidak ada pembatalan pada periode ini.|No cancellations in this period.
Export void / cancel|Export cancellations
Belum tercatat|Not recorded
Mengirim pesanan…|Sending order…
Mohon tunggu sebentar.|Please wait a moment.
Pesanan sudah terkirim|Order sent successfully
Pesanan tersimpan untuk kasir dan antrean section.|Order saved for the cashier and preparation queues.
Kembali ke pemilihan meja…|Returning to table selection…
Pesanan sudah tersimpan|Order already saved
Pesanan belum terkonfirmasi|Order not confirmed
Muat ulang untuk melihat pesanan.|Refresh to view the order.
Basket tetap tersimpan. Coba kirim ulang dengan request yang sama.|Your basket is preserved. Retry using the same request.
Kembali|Back
Pasang SUMS POS|Install SUMS POS
Di Chrome Android, buka menu ⋮ → Install app / Tambahkan ke layar utama. Setelah dipasang, buka melalui ikon SUMS POS.|In Chrome on Android, open ⋮ → Install app / Add to home screen. Then launch the SUMS POS icon.
Realtime terhubung|Realtime connected
Menghubungkan Realtime…|Connecting to Realtime…
Realtime terputus · sinkronisasi cadangan aktif|Realtime disconnected · recovery sync active
Offline · transaksi memerlukan internet|Offline · transactions require internet
Nama area|Area name
Simpan area|Save area
Nama meja|Table name
Kapasitas tamu|Guest capacity
Ketersediaan|Availability
Simpan meja|Save table
Jumlah meja|Table count
Meja otomatis diberi nomor. Isi kapasitas per meja atau terapkan sekaligus.|Tables are numbered automatically. Set each capacity or apply it to a range.
Kapasitas untuk rentang meja|Capacity for a table range
Dari meja|From table
Sampai meja|To table
Terapkan|Apply
Kapasitas|Capacity
Mengurangi jumlah meja menonaktifkan meja terakhir. Meja dengan pesanan aktif harus diselesaikan dahulu.|Reducing the count deactivates the last tables. Complete their open orders first.
+ Area / layer|+ Area / floor
Edit area|Edit area
Jumlah & kapasitas meja|Table count & capacities
+ Reservasi meja|+ Table reservation
Lihat daftar meja|Table list
Lihat layout|View layout
Atur posisi · drag & drop|Arrange tables · drag & drop
Belum ada meja. Pilih Jumlah & kapasitas meja untuk mulai.|No tables yet. Choose Table count & capacities to get started.
Owner perlu menambahkan area dan meja di Back Office.|The owner must add areas and tables in Back Office.
Tamu datang / lepas|Guest arrived / release
Reservasi meja|Reserve table
Waktu kedatangan (opsional)|Arrival time (optional)
Meja oranye diblokir sampai kasir melepas reservasi.|Orange tables stay blocked until the cashier releases the reservation.
Simpan reservasi|Save reservation
Lepas reservasi?|Release reservation?
Meja akan tersedia untuk dipilih waiter.|The table will become available to waiters.
Lepas reservasi|Release reservation
Restaurant & waiter|Restaurant & waiter
Aktifkan mode Restaurant|Enable Restaurant mode
Aktifkan waiter|Enable waiter
PIN pembatalan kasir · 6 angka|Cashier cancellation PIN · 6 digits
Simpan pengaturan Restaurant|Save Restaurant settings
Waiter memilih meja dan nama tamu sebelum memasukkan menu. Kitchen/Bar mengikuti kategori pada Logo & pengaturan cetak.|Waiters choose a table and guest before adding products. Kitchen/Bar routing follows the categories in Logo & printing settings.
Meja · area / layer|Tables · areas / floors
Diskon pembayaran|Checkout discounts
+ Tambah diskon|+ Add discount
Jenis|Type
Persentase|Percentage
Nominal IDR|Fixed amount (IDR)
Nilai|Value
Minimum belanja IDR|Minimum spend (IDR)
Maksimum potongan IDR (opsional)|Maximum discount (IDR, optional)
Mulai (waktu perangkat)|Starts (device time)
Berakhir (waktu perangkat)|Ends (device time)
Simpan diskon|Save discount
Konfirmasi cetak fisik|Confirm physical printing
Pastikan slip sudah keluar dari printer. Status ini merupakan konfirmasi operator.|Confirm the slip has physically printed. This status is confirmed by the operator.
Slip sudah tercetak|Slip has printed
Cetak|Print
Konfirmasi tercetak|Confirm printed
Antrean Kitchen / Bar|Kitchen / Bar queue
Pesanan otomatis diarahkan ke section. Android + Bluetooth: cetak masih melalui dialog sistem sampai koneksi printer tersedia.|Orders are routed automatically to sections. Android + Bluetooth printing uses the system dialog until a printer integration is available.
Tidak ada antrean menunggu.|No pending print jobs.
Tax & service|Tax & service
Tax (%)|Tax (%)
Service (%)|Service (%)
Tax juga dikenakan pada service|Apply tax to service charges too
Berlaku untuk pesanan baru. Tarif pesanan yang sudah dibuat tetap tersimpan.|Applies to new orders. Existing order rates stay unchanged.
Simpan tax & service|Save tax & service
Diskon berlaku|Available discount
Tanpa diskon|No discount
Menu sebelum diskon|Menu before discount
Diskon|Discount
Total tagihan|Bill total
Metode pembayaran|Payment methods
Metode|Method
Nominal untuk bill (IDR)|Amount allocated to bill (IDR)
Tunai diterima|Cash received
Referensi transaksi (opsional)|Transaction reference (optional)
Hapus bagian|Remove part
+ Split pembayaran|+ Split payment
Pastikan pembayaran kartu, QR atau transfer sudah berhasil sebelum dicatat.|Confirm card, QR or transfer payment has succeeded before recording it.
Menghitung…|Calculating…
Konfirmasi pembayaran|Confirm payment
Laporan pembayaran|Payment report
Seluruh transaksi lunas pada periode terpilih, semua kategori. Split dihitung menurut nominal tiap metode.|All paid transactions in the selected period, across all categories. Split payments are counted by each method's allocated amount.
Total diterima|Total collected
Tax / service|Tax / service
Belum ada pembayaran.|No payments yet.
Kasir pembayaran|Payment cashier
PEMBUAT PESANAN|ORDER CREATED BY
KASIR|CASHIER
METODE|METHOD
NOMINAL|AMOUNT
Export laporan pembayaran|Export payment report
Kartu kredit|Credit card
Kartu debit|Debit card
Transfer bank|Bank transfer
Lainnya|Other
Kasir|Cashier
Reservasi|Reserved
Terisi|Occupied
Tersedia|Available
Waktu belum ditentukan|Time not specified
Riwayat pesanan|Order history
Simpan pengaturan printer|Save printer settings
Perubahan tersimpan di server|Changes saved to server
Stok tidak cukup|Insufficient stock
Stok varian tidak cukup|Insufficient variant stock
Isi nama tamu|Enter the guest name
Kosongkan keranjang sebelum mengubah meja|Empty the basket before changing the table
Koneksi internet diperlukan untuk mengirim pesanan|An internet connection is required to send orders
Koneksi internet diperlukan untuk menyimpan perubahan|An internet connection is required to save changes
Koneksi gagal. Coba lagi.|Connection failed. Please retry.
Login diperlukan|Login required
Silakan login|Please log in
Akses bisnis atau izin ditolak|Workspace access or permission denied
Meja sedang digunakan. Muat ulang ketersediaan meja|Table is occupied. Refresh table availability
Meja masih direservasi. Kasir harus melepas reservasi dahulu|Table is reserved. The cashier must release it first
Mode waiter belum diaktifkan oleh owner|The owner has not enabled waiter mode
Pilih meja dan isi nama tamu terlebih dahulu|Select a table and enter the guest name first
PIN tidak benar|Incorrect PIN
Owner perlu mengatur PIN pembatalan|The owner must set a cancellation PIN
Batas percobaan PIN tercapai. Coba kembali setelah 15 menit|PIN attempt limit reached. Retry after 15 minutes
Total bagian pembayaran harus sama dengan tagihan|Payment parts must equal the bill total
Total semua bagian harus sama dengan tagihan|All payment parts must equal the bill total
Tunai diterima kurang dari alokasi cash|Cash received is less than the cash allocation
Diskon tidak berlaku|Discount is not valid
Pesanan tidak aktif|Order is not open
Pesanan tidak ditemukan|Order not found
Pilih varian produk|Choose a product variant
Produk utama tidak aktif|The main product is inactive
Catat pembayaran tunai|Record cash payment
Uang tunai diterima|Cash received
`;
const toEnglish=new Map(),englishLower=new Map();for(const line of rows.trim().split('\n')){const [id,en]=line.split('|');if(id&&en){toEnglish.set(id,en);if(!englishLower.has(id.toLocaleLowerCase()))englishLower.set(id.toLocaleLowerCase(),en)}}
export function translate(value){const text=String(value??'');if(language==='id')return text;const trimmed=text.trim();let result=toEnglish.get(trimmed)||englishLower.get(trimmed.toLocaleLowerCase());if(result){if(trimmed===trimmed.toUpperCase()&&/[A-Z]/.test(trimmed))result=result.toUpperCase();return text.replace(trimmed,result)}
 const patterns=[[/^Pilih varian · /,'Choose variant · '],[/^(\d+) bill dibatalkan · nilai bill (.+)\. Tidak dihitung sebagai penjualan atau pembayaran\.$/,'$1 cancelled bills · bill value $2. Excluded from sales and payments.'],[/^(\d+) meja aktif · (\d+) kapasitas tamu\. (.*)$/,'$1 active tables · $2 guest capacity. $3'],[/^Buka basket, (\d+) item$/,'Open basket, $1 items'],[/^Submit pesanan senilai /,'Submit order for '],[/^Kurangi /,'Decrease '],[/^Tambah /,'Add '],[/^Nama meja (\d+)$/,'Table name $1'],[/^(\d+) tersedia(.*)$/,'$1 available$2'],[/^(\d+) tamu$/,'$1 guests'],[/^(\d+) menit$/,'$1 min'],[/^(\d+) tersisa$/,'$1 left'],[/^(\d+) transaksi lunas$/,'$1 paid transactions'],[/^(\d+) produk$/,'$1 products'],[/^(\d+) anggota terlihat$/,'$1 visible members'],[/^(\d+) baris belum punya HPP$/,'$1 lines have no COGS'],[/^(\d+) bagian pembayaran$/,'$1 payment parts'],[/^(\d+) transaksi memakai split pembayaran\.$/,'$1 transactions used split payment.'],[/^Pembayaran (\d+)$/,'Payment $1'],[/^Simpan (\d+) meja$/,'Save $1 tables'],[/^Basket · (\d+) item$/,'Basket · $1 items'],[/^(\d+) item · Tekan untuk submit pesanan$/,'$1 items · Tap to submit order'],[/^3\. Pilih menu · /,'3. Choose products · '],[/^Sejak /,'Since '],[/^Pembuat: /,'Created by: '],[/^Kasir: /,'Cashier: '],[/^Alasan batal: /,'Cancellation reason: '],[/^Mulai Rp/,'From Rp'],[/^Edit (.+) meja$/,'Edit $1 table'],[/^Catatan /,'Note: '],[/^Bayar /,'Pay '],[/^Load & bayar /,'Load & pay '],[/^Varian · /,'Variants · '],[/ · pilih varian$/,' · choose a variant'],[/^Edit area \/ layer$/,'Edit area / floor'],[/^Tambah area \/ layer$/,'Add area / floor'],[/^Edit diskon$/,'Edit discount'],[/^Tambah diskon$/,'Add discount'],[/^Meja · /,'Tables · '],[/^Printer Waiter$/,'Waiter printer'],[/^Printer Kasir$/,'Cashier printer'],[/^Dialokasikan (.+) · sisa (.+)$/,'Allocated $1 · remaining $2']];for(const [pattern,replacement] of patterns)if(pattern.test(trimmed))return text.replace(trimmed,trimmed.replace(pattern,replacement));return text}
let protectedValues=new Set();export function protectUserText(values){protectedValues=new Set(values.filter(Boolean).map(String))}
export function localize(root){if(typeof document==='undefined'||!root)return;document.documentElement.lang=language;const visit=node=>{if(node.nodeType===3){if(node.parentElement?.closest('[data-usertext],script,style,input,textarea')||protectedValues.has(node.textContent.trim()))return;const translated=translate(node.textContent);if(translated!==node.textContent)node.textContent=translated;return}if(node.nodeType!==1)return;for(const key of ['placeholder','aria-label','title'])if(node.hasAttribute(key)){const value=node.getAttribute(key),translated=translate(value);if(translated!==value)node.setAttribute(key,translated)}for(const child of [...node.childNodes])visit(child)};visit(root)}
export function observeTranslations(){if(typeof document==='undefined')return;const observer=new MutationObserver(mutations=>{for(const m of mutations){if(m.type==='characterData')localize(m.target.parentElement);else for(const n of m.addedNodes)localize(n)}});for(const id of ['app','modal','toast']){const el=document.getElementById(id);if(el)observer.observe(el,{subtree:true,childList:true,characterData:true})}setLanguage(language)}
