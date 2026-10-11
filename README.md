# Dynamic Notch – mały notch z informacjami jak w Dynamic Island

Opracował ks. Piotr Bułka

Małe czarne wcięcie na środku paska menu, w stylu MacBooka (wersja 1.7.1).
Wcięcie pokazuje to, czego macOS sam nie pokazuje: co działa w tle i co jest podłączone.
Głośność i jasność pokazuje sam system – wcięcie ich nie powiela.

**We wcięciu:**
- grana muzyka (Muzyka, Spotify) – ma pierwszeństwo: okładka, tytuł, korektor w barwach okładki;
  kliknięcie okładki otwiera odtwarzacz,
- wydarzenie z Kalendarza – tylko na chwilę (8 s): 15 min przed i w chwili rozpoczęcia pojawia się
  karta (z przyciskiem **„Dołącz”**, gdy jest link do Zoom, Meet, Teams lub FaceTime) i znika;
  wcięcie nie wyświetla wydarzeń na stałe,
- włączenie kamery lub mikrofonu – tylko krótka informacja (ok. 3 s), muzyka zostaje na wierzchu,
- podłączenie AirPods i innych urządzeń Bluetooth – duża karta,
- bateria – ostrzeżenia przy 20% i 10%, komunikat „Naładowano”, podłączenie zasilacza.

**Na co dzień i praca (nowość w 1.5):**
- **Minutnik i stoper** – w panelu, zakładka „Narzędzia”; w trakcie odliczania wcięcie pokazuje czas,
  a na koniec karta i dźwięk,
- **Półka na pliki** – przeciągnij plik na wcięcie: lewa połowa karty odkłada go na półkę,
  prawa wysyła przez **AirDrop**; z półki (zakładka „Półka”) plik można przeciągnąć do dokumentu,
  otworzyć albo wysłać,
- **Zrzut ekranu** – po ⌘⇧3 / ⌘⇧4 na chwilę miniatura: kliknięcie otwiera, przeciągnięcie wstawia
  do dokumentu, „Na półkę” odkłada,
- **„Skopiowano”** – krótki znak przy ⌘C i lista ostatnio skopiowanych tekstów w zakładce „Półka”
  (kliknięcie kopiuje ponownie; historia tylko w pamięci, hasła są pomijane),
- **Skupienie** – krótka informacja przy włączeniu i wyłączeniu trybu Skupienia,
- **Nagrywanie ekranu, rzutnik, AirPlay** – informacja przy rozpoczęciu nagrywania (i czerwona kropka
  we wcięciu w trakcie) oraz przy podłączeniu ekranu.

**Panel (kliknięcie wcięcia lub ⌃⌥Spacja)** – cztery zakładki:
- **Teraz:** odtwarzacz w barwach okładki z przewijanym paskiem postępu, suwaki głośności
  i jasności (do szybkiej zmiany), **rozwijana lista wszystkich połączonych urządzeń**
  (Bluetooth, USB, ekrany i AirPlay), najbliższe wydarzenie,
- **Tydzień:** wydarzenia z najbliższych 7 dni (z „Dołącz”) i przypomnienia na dziś do odhaczenia.
  Kliknięcie nagłówka **Kalendarz** lub **Przypomnienia** (albo pozycji) otwiera właściwą aplikację,
- **Narzędzia:** po lewej minutnik (1–60 min, +1 min) i stoper, po prawej lista **„Do zrobienia”**
  (wpisz i naciśnij Enter; kółko odhacza, × usuwa; lista zostaje po ponownym uruchomieniu),
- **Półka:** odłożone pliki i ostatnio skopiowane teksty.

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
   - **Kalendarz** – przy pierwszym rozwinięciu panelu,
   - **Biurko** – przy pierwszym zrzucie ekranu (miniatura zrzutu).

## Obsługa

- **Kliknięcie** wcięcia – rozwija panel. Odsunięcie kursora lub kliknięcie obok – zwija.
- **⌃⌥Spacja** – rozwiń / zwiń z klawiatury (skrót można zmienić w Ustawieniach).
- **Esc** – zwiń panel, **⌘1–⌘4** – zakładki panelu.
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

- 1.4.3: po wyjściu programu z pełnego ekranu wcięcie wraca od razu (wcześniej potrafiło zniknąć).

- 1.4.4: w pełnym ekranie wcięcie samo mierzy, po jakim czasie macOS chowa pasek menu, i chowa się razem z nim.

- 1.4.5: wydarzenia nie wiszą już stale we wcięciu – pokazują się tylko na chwilę o właściwej porze.

## Wersja 1.5 – co nowego

Minutnik i stoper, półka na pliki z AirDrop, miniatura zrzutu ekranu, „Skopiowano” z historią
schowka, informacja o Skupieniu, nagrywaniu ekranu i podłączeniu rzutnika / AirPlay.
Każdą z tych funkcji można wyłączyć w Ustawieniach („Na co dzień i praca”).

## Wersja 1.6 – co nowego

- Rozwijana lista wszystkich połączonych urządzeń w zakładce „Teraz”.
- Lista „Do zrobienia” w „Narzędziach”; minutnik i stoper razem po lewej stronie.
- Poprawiona animacja: panel rozwija się płynnie od góry do dołu, treść odsłania się razem z kształtem.

## Wersja 1.7 – pełniejsza integracja z macOS

- **Skupienie:** gdy jest włączone, wcięcie pokazuje tylko ważne powiadomienia (spotkania, minutnik,
  bateria, kamera i mikrofon); „Skopiowano”, urządzenia czy zrzuty ekranu czekają.
- **Centrum powiadomień:** koniec minutnika i początek spotkania trafiają też do Centrum powiadomień –
  ale tylko wtedy, gdy od minuty nie używasz Maca lub ekran śpi (bez podwójnych komunikatów).
- **Kolor akcentu** z Ustawień systemowych (przyciski, podświetlenia).
- **Konkretne wydarzenie i przypomnienie:** kliknięcie otwiera właśnie je w Kalendarzu / Przypomnieniach.
- **Klawiatura:** Esc – zwiń panel, ⌘1–⌘4 – zakładki, ⌘W – zamknij; własny skrót do rozwijania
  (Ustawienia → Ogólne → Skrót klawiszowy); działa ⌘C / ⌘V w polu zadań.
- **Ustawienia w stylu Apple:** zakładki Ogólne, Wcięcie, Narzędzia.
- **Prywatność schowka:** w tle wcięcie wie tylko, ŻE coś skopiowano – treść czyta wyłącznie przy włączonej
  „Historii schowka” (domyślnie wyłączona; historię ma też Spotlight w macOS 26).
- **Zamknięta klapa:** przy pracy na samym monitorze wcięcie pojawia się na monitorze głównym.
- **Bateria:** w trybie niskiego zużycia energii wszystko jest sprawdzane rzadziej.
- **Aktualizacje:** raz dziennie sprawdza GitHub i na chwilę pokazuje „Dostępna wersja …” z przyciskiem Pobierz.
- **Język:** interfejs po polsku, a gdy system jest w innym języku – po angielsku.
- **Skróty (aplikacja Skróty, Siri, Touch Bar):** adresy
  `dynamicnotch://minutnik?min=10`, `dynamicnotch://stoper`, `dynamicnotch://zadanie?tekst=Kupić chleb`,
  `dynamicnotch://panel`, `dynamicnotch://ustawienia` (w Skrótach: akcja „Otwórz adresy URL”).
- Porządki w kodzie: usunięte pozostałości po wskaźnikach głośności/jasności i starych widokach.

## Wersja 1.7.1

- Nowa animacja rozwijania: okno wcięcia ma stały rozmiar, a kształt rośnie płynnie od góry do dołu
  (bez przeskoków i spóźnionego powiększania okna); cień rośnie razem z panelem.
- Poza kształtem wcięcia kliknięcia przechodzą do paska menu i programów.

## Gdy coś nie działa

Prawy przycisk na wcięciu → **Pokaż dziennik zdarzeń** – zapisuje się tam m.in. położenie paska menu,
podłączane urządzenia i komunikaty o brakujących zgodach. Ten plik warto przesłać.

Dziennik: `~/Library/Logs/DynamicNotch.log`

© 2026 ks. Piotr Bułka
