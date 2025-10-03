# 🩸 Glucose Monitor App

Aplikasi Flutter untuk monitoring kadar glukosa darah secara real-time dengan integrasi Firebase dan sistem autentikasi yang lengkap.

## 📱 Tentang Aplikasi

Glucose Monitor App adalah aplikasi mobile yang dikembangkan menggunakan Flutter untuk memantau kadar glukosa darah secara real-time. Aplikasi ini menampilkan data prediksi glukosa yang diperoleh dari sensor IoT dan memberikan indikator status kesehatan berdasarkan nilai glukosa yang terbaca.

## ✨ Fitur Utama

- **🔐 Sistem Autentikasi Lengkap**
  - Login dengan Email & Password
  - Login dengan Google Sign-In
  - Registrasi akun baru
  - Reset password
  - Auto-login untuk pengguna yang sudah login

- **📊 Monitoring Real-time**
  - Tampilan nilai glukosa secara real-time
  - Status indikator kesehatan (Normal/High/Low)
  - Animasi visual yang menarik
  - Update otomatis dari Firebase Database

- **🎨 UI/UX Modern**
  - Desain modern dengan Material 3
  - Animasi smooth dan interaktif
  - Gradient background yang menarik
  - Tema warna yang konsisten (Merah, Hijau, Putih)

## 🛠️ Teknologi yang Digunakan

- **Framework**: Flutter 3.7.2+
- **Backend**: Firebase
  - Firebase Authentication (Login/Register)
  - Firebase Realtime Database (Data glukosa)
  - Firebase Core
- **Autentikasi**: Google Sign-In
- **Platform**: Android, iOS, Web, Windows, macOS, Linux

## 📦 Dependencies Utama

```yaml
dependencies:
  flutter:
    sdk: flutter
  firebase_core: ^3.14.0
  cloud_firestore: ^5.6.9
  firebase_database: ^11.3.7
  firebase_auth: ^5.1.0
  google_sign_in: ^6.1.6
```

## 🏗️ Struktur Proyek

```
lib/
├── main.dart                 # Entry point aplikasi
├── firebase_options.dart     # Konfigurasi Firebase
├── screens/
│   ├── login_screen.dart     # Halaman login
│   └── signup_screen.dart    # Halaman registrasi
└── services/
    └── auth_service.dart     # Service autentikasi
```

## 🚀 Cara Menjalankan Aplikasi

### Prasyarat
- Flutter SDK 3.7.2 atau lebih baru
- Dart SDK
- Android Studio / VS Code
- Firebase Project (sudah dikonfigurasi)

### Langkah Instalasi

1. **Clone repository**
   ```bash
   git clone <repository-url>
   cd glucose_app
   ```

2. **Install dependencies**
   ```bash
   flutter pub get
   ```

3. **Konfigurasi Firebase**
   - Pastikan file `google-services.json` (Android) sudah ada di `android/app/`
   - Pastikan konfigurasi Firebase sudah benar di `firebase_options.dart`

4. **Jalankan aplikasi**
   ```bash
   flutter run
   ```

## 📈 Data Glukosa

Aplikasi membaca data glukosa dari Firebase Realtime Database dengan struktur:
```
glucose_predict/
└── prediction: <nilai_glukosa_double>
```

### Status Glukosa
- **Normal**: 70-140 mg/dL (Hijau)
- **Low**: < 70 mg/dL (Biru)
- **High**: > 140 mg/dL (Merah)

## 🔥 Konfigurasi Firebase

### Realtime Database Rules
```json
{
  "rules": {
    "glucose_predict": {
      ".read": "auth != null",
      ".write": "auth != null"
    }
  }
}
```

### Authentication
Aplikasi mendukung:
- Email/Password Authentication
- Google Sign-In
- Password Reset

## 🎨 Tema & Desain

- **Primary Color**: `#B71C1C` (Bold Red)
- **Secondary Color**: `#FDECEC` (Light Red Background)  
- **Accent Color**: `#2E7D32` (Healthy Green)
- **Font**: Roboto
- **Design System**: Material 3

## 📱 Platform Support

- ✅ Android

## 🤝 Kontribusi

Jika Anda ingin berkontribusi pada proyek ini:

1. Fork repository
2. Buat branch feature (`git checkout -b feature/AmazingFeature`)
3. Commit perubahan (`git commit -m 'Add some AmazingFeature'`)
4. Push ke branch (`git push origin feature/AmazingFeature`)
5. Buat Pull Request

## 📄 Lisensi

Proyek ini dibuat untuk keperluan akademik Mata Kuliah IoT.

## 👥 Tim Pengembang

Dikembangkan oleh mahasiswa Politeknik Negeri Semarang.

---

**⚠️ Catatan Penting**: 
- Aplikasi ini untuk keperluan akademik dan demonstrasi
- Data glukosa dikirim dari sensor IoT
