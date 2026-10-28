# Compilación a un ejecutable nativo y una imagen mínima con solo lo que necesita para arrancar.
FROM dart:3.13.6 AS compilacion
WORKDIR /app
COPY pubspec.yaml pubspec.lock ./
RUN dart pub get
COPY . .
RUN dart pub get --offline && dart compile exe bin/servidor.dart -o /app/servidor

FROM scratch
COPY --from=compilacion /runtime/ /
COPY --from=compilacion /app/servidor /app/servidor
USER 65532:65532
EXPOSE 8090
ENTRYPOINT ["/app/servidor"]
