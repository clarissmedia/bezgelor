# GAMEPLAY REPAIR — Bezgelor / WildStar 16042

Date : 20 octobre 2026. Base : `52ea15500a5fcba71a5ad1b566f8ad0e9e0b0083`.
Branche de travail : `repair/gameplay-16042`.

## État réel

**Des corrections sont testées, mais le gameplay complet n'est pas validé. Aucun redéploiement ni reconstruction de l'image serveur n'a été effectué.**

La reprise conserve les 20 fichiers modifiés et les 4 fichiers créés avant l'interruption. L'historique de la session `01a15550-a848-72d3-bff5-272fb71dab7e`, le patch sauvegardé dans `SAUVEGARDE_CODEX_20261020` et les diagnostics `gameplay-repair` ont été examinés. La session précédente n'avait pu accéder à Docker ; les compilations et tests de cette reprise utilisent désormais un SDK Elixir isolé.

Les conteneurs `wildstar-bezgelor-server-1` et `wildstar-bezgelor-postgres-1` restent sur leur installation existante. Aucun compte, personnage, volume de production, client WildStar ou fichier de NexusForever n'a été modifié. Les seules migrations exécutées concernent une base de tests éphémère distincte.

Dernier contrôle en lecture seule : serveur et PostgreSQL `healthy`, **1 compte et 2 personnages** dans la base Bezgelor. Ces chiffres concernent Bezgelor, pas les bases historiques NexusForever.

## Causes et corrections

### Quêtes

- `ClientQuestAccept 0x035B` manquait du registre des opcodes. Les enveloppes doivent transmettre leur opcode interne au gestionnaire ; `Connection` dispose maintenant de ce champ, y compris lorsqu'un struct est utilisé.
- Le paquet d'acceptation fait **56 bits** : emplacement d'inventaire sur 9 bits, index de sac sur 32 bits, quête sur 15 bits. Il ne contient pas de GUID de PNJ. Les formats d'abandon et de restitution ont également été confrontés à la référence locale NexusForever.
- Les réponses utilisent les véritables paquets `ServerQuestStateChange 0x035C`, `ServerQuestObjectiveUpdate 0x0361` et `ServerQuestInit 0x035F`, avec leur alignement continu des bits. L'historique des quêtes terminées est réémis à la connexion.
- L'acceptation et l'abandon ne sont plus annoncés lorsque l'opération durable échoue. Une restitution immédiate sauvegarde la progression et l'état obtenu avant la vérification en base.
- Les colonnes d'objectifs sont `objective0`, `objective01` … `objective05`. L'ancien accès à `objective1` … `objective5` omettait les objectifs secondaires.
- Les événements de progression envoyaient encore des paquets non chiffrés. Le chemin `Connection.handle_info({:game_event, ...})` utilise maintenant l'enveloppe monde chiffrée. Un test TCP déchiffre effectivement la réponse et vérifie son opcode interne.
- L'XP de récompense de quête était seulement annoncée au client. Elle est désormais persistée avant notification et vérifiée par une nouvelle lecture du personnage.

### Spawns, GUID et déplacements

Le fichier `creature_spawns.json` de l'image active est identique à celui des sources : SHA-256 `d7668b275782315dfdbb21b5f9f30fe1558725b5a12bbdf9cb6f0853f99ff733`.

Audit reproductible en lecture seule :

```powershell
Set-Location E:\WILDSTAR\BEZGELOR\source
python tools/audit_gameplay_spawns.py
```

Pour le monde **426 / NorthernWilds**, autour de `{4110.71, -658.6249, -5145.48}` :

| Rayon en unités | Apparitions |
|---|---:|
| 200 | 36 |
| 500 | 383 |
| 1 000 | 656 |
| Monde complet | 673 |

Les 36 apparitions initiales correspondent aux journaux. Elles incluent 22 entrées de faction 171, 8 de faction 219, 2 de faction 1208 et 4 de faction 0. Les identifiants de faction seuls ne prouvent pas l'hostilité. Deux yétis se trouvent vers la limite du rayon initial, à environ 196–197 unités, d'après le diagnostic sauvegardé.

Deux défauts indépendants expliquent les interactions et la visibilité :

1. Les GUID serveur étaient construits sur 64 bits alors que les créations et sélections transmettent 32 bits. Le serveur ne retrouvait donc pas nécessairement l'entité sélectionnée. Les nouveaux GUID, les GUID stables des personnages et ceux des cadavres utilisent maintenant le même espace sur 32 bits.
2. Le chemin `ClientEntityCommand` ne mettait pas à jour la position serveur ni les créatures visibles après l'entrée en jeu. Il actualise maintenant l'instance, la session, la position sauvegardée et les apparitions dans un rayon de 200 unités. Les créations et destructions sont envoyées lors des passages de portée, sans doublon sur une position inchangée.

Le relais des commandes vers les autres joueurs conserve les bits après son en-tête sur 7 bits. Les paquets tronqués et les compteurs non représentables sont rejetés. Les modèles inconnus interrompent le décodage, sans deviner la suite ; leur gestion complète reste une limite.

Le paquet `ServerEntityDestroy` a été corrigé selon la référence : GUID sur 32 bits puis un booléen. Les PNJ sont résolus dans l'instance réelle, sans déduire un identifiant de créature à partir du compteur du GUID. Les interactions vides ne déclenchent plus de dialogue.

### Combats et progression

- La sélection de cible est conservée dans la session.
- Les sorts instantanés appliquaient leurs effets au lanceur, même lorsqu'une autre cible était sélectionnée. Le chemin utilise désormais cette cible et la bonne instance ; un test passe réellement par `EntitySelectHandler` puis `SpellHandler`.
- Un coup fatal unique perdait le participant ajouté à l'IA avant la résolution de mort. L'état d'IA actualisé est maintenant transmis au traitement de mort.
- Les dégâts actualisent aussi le registre général d'entités. Le ciblage ne retrouve plus une copie avec des points de vie périmés.
- Des tests vérifient le crédit du tueur, l'événement d'objectif, l'XP de mise à mort sauvegardée, le refus de dégâts supplémentaires sur un mort et la remise en vie via le véritable message de respawn. Le test déclenche le message du minuteur sans attendre son délai ; cela ne valide pas son affichage dans le client.

## Vérifications

Environnement : image SDK déjà présente `hexpm/elixir:1.19.4-erlang-28.2-debian-trixie-20251208-slim`, conteneur `bezgelor-gameplay-test`. Dépendances et compilation dans `/tmp` ; sources montées depuis ce dépôt. Base distincte `bezgelor-gameplay-test-db`, stockage éphémère, réseau séparé, aucun port publié, aucun volume de production attaché.

- **Compilation complète : réussie**, avec `mix compile --force --warnings-as-errors`.
- **Formatage de tous les fichiers Elixir modifiés : réussi** avec `mix format --check-formatted` sur ces fichiers.
- **Suite ciblée finale : 529 tests et 1 doctest, zéro échec**, graine `807177`. Cinq anciens tests d'intégration sont exclus ; les 13 parcours de `gameplay_repair_test.exs` sont exécutés, avec leur base réelle de tests.
- `mix precommit` a été exécuté. L'alias était absent à la racine : il est maintenant défini. Son contrôle global de formatage reste bloqué par des fichiers hors réparation ; la même vérification échoue sur le commit amont intact.
- Une suite complète et une comparaison sur une copie intacte du commit amont ont été exécutées avec la graine `807177`. Le commit amont présente déjà **54 échecs dans `bezgelor_world`** dans cet environnement. La version corrigée en présente **64** : les dix échecs supplémentaires appartiennent à la cascade d'arrêt du superviseur dans `CombatEdgeCasesTest`, dont le même arrêt se reproduit aussi sur la référence. Les autres problèmes comprennent des fixtures sans royaume valide. Les 13 nouveaux parcours de gameplay passent également dans cette exécution globale. Ce résultat ne permet pas de déclarer la suite globale validée.

Journaux dans `source/logs/gameplay-repair/` ; ils sont volontairement exclus de Git. La copie de référence et les dépendances de tests sont séparées des sources modifiées et du serveur en service.

Commande ciblée reproductible, dans un environnement Elixir utilisant exclusivement une base de tests :

```sh
MIX_ENV=test mix test \
  apps/bezgelor_core/test \
  apps/bezgelor_data/test/store_quest_test.exs \
  apps/bezgelor_protocol/test/packets/quest_packets_test.exs \
  apps/bezgelor_protocol/test/packets/gameplay_quest_wire_test.exs \
  apps/bezgelor_protocol/test/entity_command_decoder_test.exs \
  apps/bezgelor_world/test/gameplay_repair_test.exs \
  apps/bezgelor_world/test/quest/quest_handler_test.exs \
  apps/bezgelor_world/test/quest/session_quest_manager_test.exs \
  apps/bezgelor_world/test/session_quest_manager_events_test.exs \
  apps/bezgelor_world/test/world/creature_state_test.exs \
  apps/bezgelor_world/test/loot_test.exs \
  apps/bezgelor_world/test/handler/npc_handler_dialogue_test.exs \
  --seed 807177
```

## Limites bloquant une déclaration de gameplay fonctionnel

- **Compétences réelles de classe :** `BezgelorCore.Spell.get_from_game_data/1` construit encore des sorts Spell4 avec `target_type: :self` et `effects: []`. Le test de lancement utilise le sort de démonstration Quick Strike ; il ne prouve pas le fonctionnement des compétences de la barre du personnage. Les tables et calculs réels d'effets doivent être intégrés et testés. Aucun dégât artificiel n'a été ajouté pour masquer cette limite.
- **Récompenses :** restitution et distribution ne sont pas atomiques ; le choix de récompense du paquet reste ignoré. L'XP persistée est testée, mais cela ne valide pas tous les objets, monnaies, choix et scénarios d'échec partiel.
- **Visibilité :** actualisée sur les commandes de position prises en charge. Le retour visuel d'une créature ressuscitée pour un joueur immobile et les modèles de mouvement non décodés nécessitent encore des tests et du travail.
- **`0x0799` / `0x079A` :** absents de la table d'opcodes de la référence locale NexusForever 2021. Leur signification n'est pas démontrée ; aucun décodeur inventé ni acquittement factice n'a été ajouté.
- **Ranch `:einval` :** les journaux montrent `ranch_init`, ligne 101, sur le listener royaume. `deployment/check-health.exs` ouvre puis ferme immédiatement les ports TCP ; le démarrage de connexion exige ensuite un `peername` réussi. Cette course explique plausiblement le bruit périodique, indépendamment de `0x035B`. Elle n'a pas été corrigée sans test déterministe.
- **Aucun essai client en jeu n'a été effectué.** Durek, les compétences réelles, le loot reçu, les récompenses et la reconnexion doivent encore être validés.

Les suites sont suivies dans Beads : `source-2` (validation en jeu et opcodes), `source-3` (contrôles globaux et Ranch), `source-4` (effets réels Spell4), `source-5` (récompenses atomiques et choix).

Les sources sont conservées sur la branche `repair/gameplay-16042` du [fork de sauvegarde](https://github.com/clarissmedia/bezgelor/tree/repair/gameplay-16042). Le remote `origin` reste le dépôt amont, sur lequel le compte connecté ne dispose pas du droit de push ; le remote `gameplay` vise le fork.

## Redéploiement non destructif — commandes préparées, non exécutées

**Ne pas lancer cette reconstruction tant que les contrôles bloquants et les effets réels des compétences n'ont pas été traités.** Les commandes ciblent le Compose de l'installation, `E:\WILDSTAR\BEZGELOR\docker-compose.yml`. Celui de `source` est un autre fichier et ne décrit pas ce serveur.

Après validation des contrôles, fermer proprement le jeu pour laisser sauvegarder les sessions, puis utiliser PowerShell :

```powershell
$root = 'E:\WILDSTAR\BEZGELOR'
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$backup = Join-Path $root "backups\gameplay-redeploy-$stamp"
New-Item -ItemType Directory -Path $backup -Force | Out-Null
$compose = @('--project-directory', $root,
  '--env-file', (Join-Path $root '.env.local'),
  '--env-file', (Join-Path $root '.images.env'),
  '-f', (Join-Path $root 'docker-compose.yml'))

# Dump binaire dans le conteneur puis copie : pas de redirection binaire PowerShell 5.
docker exec wildstar-bezgelor-postgres-1 pg_dump -U bezgelor_local -d bezgelor_local -Fc -f /tmp/gameplay-before.dump
if ($LASTEXITCODE -ne 0) { throw 'Sauvegarde PostgreSQL echouee' }
docker exec wildstar-bezgelor-postgres-1 pg_restore --list /tmp/gameplay-before.dump
if ($LASTEXITCODE -ne 0) { throw 'Archive PostgreSQL illisible' }
docker cp wildstar-bezgelor-postgres-1:/tmp/gameplay-before.dump (Join-Path $backup 'bezgelor.dump')
if ($LASTEXITCODE -ne 0) { throw 'Copie de sauvegarde echouee' }
Get-FileHash (Join-Path $backup 'bezgelor.dump') -Algorithm SHA256

# Conserver une reference vers l'image actuellement utilisee.
$oldImage = docker inspect --format '{{.Image}}' wildstar-bezgelor-server-1
if ($LASTEXITCODE -ne 0) { throw 'Image actuelle introuvable' }
docker tag $oldImage "wildstar-bezgelor-local:before-gameplay-$stamp"
if ($LASTEXITCODE -ne 0) { throw 'Sauvegarde du tag image echouee' }

# Compiler/tester les sources dans l'environnement de tests avant cette etape.
docker compose @compose build server
if ($LASTEXITCODE -ne 0) { throw 'Reconstruction echouee; serveur existant conserve' }
docker compose @compose up -d --no-deps --force-recreate server
if ($LASTEXITCODE -ne 0) { throw 'Redemarrage serveur echoue' }
docker compose @compose ps
docker compose @compose logs --since 5m --tail 150 server
docker compose @compose exec -T server /app/local/run-task config
docker compose @compose exec -T server /app/local/run-task health
```

Aucune migration de production n'est nécessaire pour ces corrections. Ne pas lancer `down -v`, `prune`, une remise à zéro ou le profil `migrate`. `--no-deps` conserve PostgreSQL et son volume `wildstar_bezgelor_pg16_data`.

Retour à l'ancienne image, sans restauration ni modification de base :

```powershell
docker tag "wildstar-bezgelor-local:before-gameplay-$stamp" 'wildstar-bezgelor-local:52ea15500a5f'
if ($LASTEXITCODE -ne 0) { throw 'Ancienne image introuvable' }
docker compose @compose up -d --no-deps --force-recreate server
```

## Validation en jeu après levée des limites et redéploiement

1. Reprendre le même personnage et noter niveau, XP, position, quêtes et inventaire avant connexion.
2. Ouvrir le dialogue de Durek, accepter « À vos ordres chef ! » : vérifier l'apparition de la quête et l'absence d'opcode `0x035B` inconnu. Répéter le clic : une seule quête doit être créée.
3. Se déconnecter puis revenir : vérifier que la quête reste active. Abandonner une quête de test puis la reprendre pour vérifier les deux transitions.
4. Marcher au-delà de la portée initiale de 200 unités : observer de nouvelles créatures, cibler un PNJ puis un monstre et vérifier que les GUID correspondent dans les journaux. Revenir en arrière pour contrôler les disparitions et réapparitions sans doublon.
5. Avec une compétence réelle de classe prise en charge, vérifier dégâts, poursuite, riposte, mort, crédit d'objectif, XP et loot. Un coup fatal unique doit aussi donner le crédit. Un cadavre ne doit pas fournir de nouveau crédit.
6. Attendre un respawn réel ; vérifier l'apparition et les points de vie, en restant immobile puis en bougeant. Cette étape distingue l'état serveur testé de la visibilité client encore à confirmer.
7. Terminer un objectif et restituer immédiatement la quête, avant le tick de sauvegarde. Vérifier XP, objets, monnaie et éventuel choix, puis refaire une connexion pour vérifier leur persistance. L'impossibilité d'obtenir une récompense doit rester visible dans les journaux.
8. Refaire une connexion après déplacement et après progression partielle ; comparer position, objectifs, XP et inventaire aux valeurs attendues.

Conserver les journaux et les observations pour chaque étape. L'état `healthy` et les tests automatisés ne remplacent pas cette validation.
