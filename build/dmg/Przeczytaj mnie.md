# Dynamic Notch – mały notch z informacjami jak w Dynamic Island

Opracował ks. Piotr Bułka

Małe czarne wcięcie na środku paska menu, w stylu MacBooka (wersja 1.4.2).
Wcięcie pokazuje to, czego macOS sam nie pokazuje: co działa w tle i co jest podłączone.
Głośność i jasność pokazuje sam system – wcięcie ich nie powiela.

**We wcięciu:**
- grana muzyka (Muzyka, Spotify) – ma pierwszeństwo: okładka, tytuł, korektor w barwach okładki;
  kliknięcie okładki otwiera odtwarzacz,
- gdy nic nie gra – najbliższe wydarzenie z Kalendarza z **najbliższych 7 dni** („jutro 9:00”, „pt 18:30”),
- 15 min przed wydarzeniem i w chwili rozpoczęcia – duża karta (z przyciskiem **„Dołącz”**, gdy jest
  link do Zoom, Meet, Teams lub FaceTime), pomiędzy – odliczanie „za 12 min”,
- włączenie kamery lub mikrofonu – tylko krótka informacja (ok. 3 s), muzyka zostaje na wierzchu,
- podłączenie AirPods i innych urządzeń Bluetooth – duża karta,
- bateria – ostrzeżenia przy 20% i 10%, komunikat „Naładowano”, podłączenie zasilacza.

**Panel (kliknięcie wcięcia lub ⌃⌥Spacja)** – dwie zakładki:
- **Teraz:** odtwarzacz w barwach okładki z przewijanym paskiem postępu, suwaki głośności
  i jasności (do szybkiej zmiany), urządzenie, najbliższe wydarzenie,
- **Tydzień:** wydarzenia z najbliższych 7 dni (z „Dołącz”) i przypomnienia na dziś do odhaczenia.
  Kliknięcie nagłówka **Kalendarz** lub **Przypomnienia** (albo pozycji) otwiera właściwą aplikację.

**Wygląd jak w macOS 27:** głęboka czerń jak sprzętowe wcięcie, delikatny refleks światła na dolnej
krawędzi, jednolite, łagodniejsze zaokrąglenia – bez ramek.

**Tryb pełnoekranowy:** wcięcie wysuwa się i chowa **razem z paskiem menu** – w tej samej chwili
i w tym samym tempie, jak element systemu.

**Praca w tle:** program działa jako agent – startuje przy logowaniu i sam się podnosi po awarii.
Wstrzymuje odświeżanie przy uśpionym ekranie (oszczędza baterię).

## Instalacja

1. Rozpakuj folder `DynamicNotch` do Pobranych.
2. W Terminalu wpisz:
   ```
   bash ~/Downloads/DynamicNotch/zrob-dmg.sh
   ```
3. W oknie instalatora przeciągnij **Dynamic Notch** na folder **Aplikacje**.
4. Uruchom Dynamic Notch z Aplikacji. Pojawi się prośba o uprawnienie **Dostępności** – włącz
   przełącznik przy „Dynamic Notch” (dzięki temu Dynamic Notch widzi, gdzie kończą się menu programu).
5. Przy pierwszym użyciu macOS zapyta jeszcze o:
   - **Przypomnienia** – lista na dziś w panelu,
   - **Bluetooth** – żeby pokazywać podłączane urządzenia,
   - **sterowanie Muzyką / Spotify** – okładka i przyciski odtwarzacza,
   - **Kalendarz** – przy pierwszym rozwinięciu panelu.

## Obsługa

- **Kliknięcie** wcięcia – rozwija panel. Odsunięcie kursora lub kliknięcie obok – zwija.
- **⌃⌥Spacja** – rozwiń / zwiń z klawiatury.
- **Prawy przycisk** na wcięciu – Ustawienia, dziennik zdarzeń, zakończenie programu.
- **Ponowne uruchomienie** Dynamic Notch z Launchpada otwiera Ustawienia.

## Jak wcięcie dba o pasek menu

- Stoi na środku, dokładnie na wysokości paska menu.
- Gdy menu programu (np. Pages) sięga środka, wcięcie przesuwa się w wolne miejsce przed ikonami.
- Gdy miejsca nie ma wcale, w spoczynku znika, a zdarzenia pokazuje na chwilę pod paskiem.
- W trybie pełnoekranowym i podczas pokazu Keynote jest schowane razem z paskiem menu – wysuwa się
  dopiero z nim; pokazuje się tylko na ekranie MacBooka, nie na rzutniku.

## Uruchamianie przy starcie Maca

Przy pierwszym uruchomieniu Dynamic Notch sam dodaje się do programów otwieranych przy
logowaniu – po każdym włączeniu Maca wcięcie pojawia się automatycznie. Można to wyłączyć
w Ustawieniach (prawy przycisk na wcięciu → Ustawienia… → „Uruchamiaj przy starcie Maca”)
albo w Ustawieniach systemowych → Ogólne → Rzeczy otwierane przy logowaniu.

## Ustawienia

Można wyłączyć każdy rodzaj informacji, wybrać rozwijanie kliknięciem albo po zatrzymaniu kursora
i włączyć uruchamianie przy logowaniu. Głośność i jasność pokazuje sam macOS.

## Wersja 1.4 – co nowego

- Kamera i mikrofon – tylko krótka informacja przy włączeniu; muzyka ma pierwszeństwo.
- Kalendarz – wydarzenia z najbliższych 7 dni, więc wcięcie prawie zawsze coś pokazuje.
- Usunięto wskaźniki głośności i jasności (pokazuje je system).
- Wygląd w stylu macOS 27 (1.4.1: usunięta dziwna ramka wokół panelu).
- Kliknięcie Kalendarza i Przypomnień w panelu otwiera te aplikacje.
- Pełny ekran: wcięcie wysuwa się i chowa razem z paskiem menu (1.4.1: chowa się w tej samej chwili co pasek).

- 1.4.2: na zwykłym biurku wcięcie jest widoczne zawsze (chowa się tylko w trybie pełnoekranowym,
  razem z paskiem menu); naprawione otwieranie okna Ustawień.

## Gdy coś nie działa

Prawy przycisk na wcięciu → **Pokaż dziennik zdarzeń** – zapisuje się tam m.in. położenie paska menu,
podłączane urządzenia i komunikaty o brakujących zgodach. Ten plik warto przesłać.

Dziennik: `~/Library/Logs/DynamicNotch.log`

© 2026 ks. Piotr Bułka
