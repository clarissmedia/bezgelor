# Quick Draw : phases et ciblage, reconstruction bornée

Date : 20 octobre 2026. Départ réellement vérifié : branche
`repair/spell4-effects-audit`, commit `7a16593`, arbre propre. Distant de travail
préexistant : `gameplay`, `https://github.com/clarissmedia/bezgelor.git`.

**Résultat : les données sont vérifiées indépendamment, mais aucun ordonnanceur
authentique des impacts ne peut encore être démontré. Quick Draw reste refusé
avant toute mutation.** Les nouveaux composants sont des diagnostics purs,
avec une garde d'idempotence indépendante. Aucun dégât, soin, déplacement,
cooldown, coût de ressource ou récompense réel n'est ajouté.

## Preuves et reproductibilité

- [Enregistrements et comparaisons intégrales](2026-10-20-quick-draw-phase-evidence.json) :
  vingt tables, **337 680 enregistrements**, tous les champs comparés entre
  `BezgelorData.Tbl` et le lecteur C# NexusForever original. Les lignes et les
  empreintes du catalogue sélectif existant sont aussi vérifiées, sans divergence.
- [Seize observations géométriques C#](2026-10-20-quick-draw-geometry-vectors.json),
  consommées par les tests Elixir : entrées, résultats et empreintes des sources.
- [Audit historique](2026-10-20-tbl-layout-audit.json) : 384 tables examinées,
  différences avec les JSON existants et comparaison Python/C# exhaustive sur
  vingt-deux tables, **346 423 enregistrements**.
- [Provenance des sources](2026-10-20-quick-draw-phase-sources.json) : chemins,
  SHA256 et liens vers les sources amont immuables.
- [Commandes et résultats de validation](2026-10-20-quick-draw-phase-validation.txt).
- [Adaptateurs reproductibles](../../tools/spell4_reference_reader/README.md).

Les originaux viennent de `E:/WILDSTAR/SERVEUR/WORLD/tbl`. Le programme
`tools/spell4_reference_reader/ReferenceReader.csproj` compile des liens vers
les fichiers originaux de `E:/WILDSTAR/SERVEUR/REWORK/Source`, dans son propre
répertoire de sortie. Le lecteur `GameTable<T>.ReadEntries` reste inchangé.
Des modèles scalaires dynamiques suivent les colonnes binaires, sans recopier
manuellement leurs valeurs. Aucun projet installé n'est construit ni modifié.

Les sources géométriques et d'exécution examinées correspondent au commit
NexusForever `f9bb26efddbf304003fc8ebf484ac75bc6be84da`, copie déjà disponible
sous `logs/spell4-engine/upstream/Source`. Les empreintes permettent de vérifier
la copie. Le SDK .NET et Python sont préexistants ; aucun paquet n'a été ajouté.
Les opérations C#/Python sur l'hôte sont des extractions et comparaisons de
fichiers. Tous les tests du code Elixir ont tourné dans le conteneur autorisé.

## Chronologie : ce qui est établi

`Spell4[43468]` donne `castTime=1000`, `channelMaxTime=1000`,
`channelInitialDelay=366`, `channelPulseTime=634`, `spellChannelFlags=0`.
Ces valeurs ne démontrent ni un instant de premier impact ni un nombre de tirs.
Les quatre références `spell4IdCastEvent00..03` sont nulles. Aucune ligne
`Spell4Thresholds` ne référence ces quatre sorts comme parent.

La racine référence `Spell4Runner[3]` et `Prerequisite[20117]`. Le runner
contient `spriteName=sprAS_Prompt_Resource`, `rate=1` et des teintes, sans
définition d'événements de canal. Le prérequis porte notamment
`prerequisiteTypeId0=15`, `value0=47439` ; il ne devient pas un coût de ressource
supposé. Les six lignes Runner sont conservées dans le catalogue existant,
relues intégralement dans la comparaison indépendante.
`Spell4CastResult` contient les résultats d'incantation (`ID=0`, `enumName=Ok`,
`combatMessageTypeEnum=49`, texte et son), pas une correspondance entre phases
et impacts. `Spell.cs::CheckCast` et `SendSpellCastResult` utilisent ces résultats
pour la validation et les messages ; ils n'apportent pas cette correspondance.

Ordre des lignes de `SpellPhase`, pour `spell4IdOwner=43468` :

| ID | orderIndex | phaseDelay brut, ms | phaseFlags brut | Instant de déclenchement prouvé |
|---:|---:|---:|---:|---|
| 5882 | 0 | 0 | 0 | Non établi |
| 5883 | 1 | 366 | 512 / 0x200 | Non établi |
| 5884 | 2 | 200 | 0 | Non établi |
| 5885 | 3 | 200 | 4 / 0x4 | Non établi |
| 5886 | 4 | 234 | 0 | Non établi |

La somme des délais vaut 1000. La séquence cumulative hypothétique serait
0/366/566/766/1000 ms, **mais la référence temporelle des délais n'est pas
démontrée**. Cette séquence n'est pas produite ni exécutée par le code.
`orderIndex` fournit un ordre de données, pas une preuve d'ordre des impacts.

Les neuf lignes `Spell4Effects` de la racine ont toutes `delayTime=0` :

| Effet | Type | phaseFlags | targetFlags | Référence explicite |
|---:|---:|---:|---:|---|
| 196513 | 26 Proxy | 2 | 1 | 43498 |
| 196514 | 26 Proxy | 4 | 1 | 43499 |
| 196515 | 26 Proxy | 8 | 1 | 43498 |
| 196516 | 26 Proxy | 8 | 1 | 43500 |
| 196517 | 26 Proxy | 2 | 1 | 43499 |
| 196518 | 26 Proxy | 4 | 1 | 43498 |
| 196519 | 26 Proxy | 8 | 1 | 43499 |
| 196521 | 80 SpellForceRemove | 8 | 1 | dataBits00=2, dataBits01=43500 ; pas un proxy |
| 196522 | 26 Proxy | 1 | 1 | 43500 |

Les masques 1/2/4/8 de cette table ne sont ni les identifiants 5882–5886, ni une
énumération de cinq phases. Le masque 4 présent dans les deux tables ne prouve
pas une correspondance. Le schéma suggère plusieurs interprétations possibles ;
aucune n'est retenue comme comportement.

Les secondaires restent séparés :

- `43498` → effet `99526`, type 8 Damage, `targetFlags=4`,
  `phaseFlags=0xffffffff`, `delayTime=0`.
- `43499` → effet `99528`, mêmes types et masques.
- `43500` → effet `99472`, type 17 Fluff, `targetFlags=1`,
  `phaseFlags=0xffffffff`, `spellDuration=990` sur le sort.

Ces correspondances viennent des tables originales, recoupées avec
`NexusForever.Game.Static/Spell/SpellEffectType.cs` et
`SpellEffectTargetFlags.cs`. Le nom du type ne suffit pas à autoriser son
exécution. Trois références à chacun des deux sorts de dégâts ne constituent
pas la preuve de six impacts. Les huit références proxy et leurs identifiants
sont conservés dans le plan et par le résolveur existant.

## Pourquoi aucun ordonnanceur n'est activé

Dans le snapshot amont inspecté :

- `NexusForever.Game/Spell/Spell.cs::Execute` appelle `SelectTargets`, puis
  `ExecuteEffects` et `CostSpell`.
- `ExecuteEffects` sélectionne les cibles par intersection de `TargetFlags`
  et appelle les gestionnaires d'effets. Il n'interprète ni `PhaseFlags` ni
  `DelayTime` et ne relie pas les lignes `SpellPhase` aux événements.
- Les occurrences de `SpellPhase`, `ChannelInitialDelay`, `ChannelPulseTime`
  et des masques de phase concernent essentiellement les modèles et tables
  chargées ; aucun interpréteur des déclencheurs de Quick Draw n'a été trouvé
  dans les sources C# inspectées. Cette conclusion est limitée à ce snapshot.
- `CancelCast` annule les événements du sort NexusForever ; cela ne définit
  pas à lui seul quelles phases doivent être exécutées avant ou après interruption.

La recherche publique a aussi consulté le [suivi officiel de la refonte des
sorts](https://github.com/NexusForever/NexusForever/issues/475) et la page de
[SpellWorks](https://github.com/NexusForever/NexusForever.SpellWorks). Ces pages
apportent du contexte, pas une définition des masques ou des événements.

`Spell4PhasePlan.build/3` expose donc l'identité, l'ordre, les délais, les
effets complets et les inconnues. `recognized_triggers` reste vide ;
`schedule/1` renvoie `{:error, :unverified_phase_triggers}`. Aucun timer n'est créé.

`Spell4EventLedger` est une garde locale testée pour un futur producteur
d'événements validé : jeton par incantation, occurrence déjà vue, annulation,
fin et limite mémoire de 4096 entrées. Les événements obsolètes ou répétés sont
ignorés. Les tests utilisent des identités synthétiques, sans attribuer de
phase réelle à un effet. La garde ne déduit pas l'équivalence entre deux arêtes
proxy distinctes ; cette équivalence dépend justement de la sémantique absente.
Elle n'est pas raccordée au monde et ne constitue pas un moteur de phases.
Le cycle `SpellManager` existant et ses protections restent inchangés.

## Télégraphes et restrictions de cible

Liens `Spell4Telegraph` relus : `39868` lie `43468` à `3693`, `6839` lie
`43498` à `3694`, `6837` lie `43499` à `3694`.

Les deux lignes `TelegraphDamage[3693/3694]` portent :

- `damageShapeEnum=8`, nommé `LongCone` dans `DamageShape.cs` ;
- `param00..05 = 3, 27, 15, 0, 20, 0` ;
- `xPositionOffset=0`, `yPositionOffset=0`, `zPositionOffset=-2`, rotation 0 ;
- `phaseFlags=0xffffffff`, `targetTypeFlags=1` ;
- `telegraphDamageFlags=4720160` pour 3693 et 64 pour 3694.

La signification opérationnelle de `param04=20`, des drapeaux de télégraphe et
du filtrage par phase n'est pas établie par l'algorithme consulté.

Les sorts d'impact référencent la contrainte `405` : `minRange=0`,
`maxRange=25`, `angle=360`, `targetCount=3`, `targetSelection=1`. La racine
référence la contrainte 0. Ces champs ne prouvent pas la priorité, le départage
ou l'ordre des cibles. `select_targets/2` refuse systématiquement la sélection
avec `:unverified_target_policy`, sans prendre les trois premières créatures.

Autres relations relues, conservées dans le fichier de preuves :

| Table | Racine | Impacts 43498/43499 |
|---|---|---|
| Spell4Base | 27638 | 27668 / 27669 |
| Spell4TargetMechanics | 1 : targetType=0, flags=1 | 6 : targetType=2, flags=16 |
| Spell4ValidTargets | 1 : targetBitmask=0 | 1 : targetBitmask=0 |
| Spell4Conditions caster | 43 : mask=1249, value=0 | 1 : mask=225, value=0 |
| Spell4Conditions target | 15 : mask=129, value=0 | 15 : mask=129, value=0 |
| Spell4Base.targetingFlags | 0 | 18 |

Les conditions CC portent notamment le masque caster `218960739` et un masque
target nul pour la ligne 2 de la racine. Les bits de conditions, les règles de
faction, les groupes de cibles et leurs priorités ne sont pas interprétés ici.
Un `targetBitmask=0` ne devient pas une autorisation universelle.
`SearchCheckTelegraph.CheckEntity` de NexusForever exclut le lanceur et teste la
géométrie ; il ne fournit pas une politique complète de faction, de ligne de
vue et de limitation à trois cibles.

## Géométrie transférable, avec portée explicite

`Spell4TelegraphGeometry.point_inside/5` est un diagnostic pur limité aux
**points de rayon nul**, cercle et cône/LongCone. Aucun rayon absent n'est
remplacé par une constante. Un rayon positif ou absent est refusé. La fonction
ne sélectionne pas de cible et ne consulte ni position vivante ni PV.

Sources précises : `Telegraph.cs::ApplyPositionOffsets`,
`ApplyRotationOffsets`, `InsideTelegraph`, `IsHitInsideAngle` ;
`MathsExtensions.cs::GetPointForTelegraph`, `GetAngle`, `GetDistance`.

Pour ce sous-ensemble de l'algorithme NexusForever :

- Les coordonnées sont X/Y/Z, les distances et angles se calculent sur XZ.
  `Rotation.X` est le yaw, 0 vers −Z, +π/2 vers −X.
- Un point déplacé d'une distance `d` à l'angle `a` devient
  `(X + cos(a)*d, Y, Z - sin(a)*d)`. L'offset Z utilise `yaw+π/2`, puis
  l'offset Y, puis l'offset X utilise `yaw+π`. L'offset de rotation s'applique après.
- Avec des rayons nuls, l'intervalle radial du cône est inclusif `[param00,param01]`.
  L'ouverture totale du calcul de référence est `param02 + param00/2`, soit
  **16,5°** ici, et non une ouverture supposée de 15°.
- Pour yaw 0 et l'offset −2 de Quick Draw, l'origine géométrique est en Z=+2.
  Un point axial Z=−25 se trouve donc à distance 27 de cette origine. Cela ne
  prouve pas l'équivalence du volume avec un rayon de 25 autour du lanceur.
- Le calcul de référence ignore la hauteur pour les cônes. Ce constat ne prouve
  pas que le jeu original ignore les collisions ou la hauteur.

Les seize résultats C# sont émis par le **Telegraph original non modifié**,
avec uniquement des adaptateurs d'interfaces et de journalisation. La recherche
de carte est interdite dans cet outil. Ils couvrent axe, arrière, côté,
distances internes/externes, voisinage des deux bords angulaires, hauteur,
translation, yaw, offsets de position/rotation et bord du cercle.
Les coordonnées sont des fixtures synthétiques ; certains vecteurs modifient
explicitement les paramètres de la ligne de base 3694 pour isoler un offset,
une rotation ou le cercle. Ils ne présentent pas ces variantes comme des
enregistrements originaux de Quick Draw.
Les tests Elixir vérifient également les frontières radiales inclusives et
une frontière angulaire exactement représentable. BEAM utilise des flottants
64 bits ; ce port n'est pas une émulation bit à bit de `MathF` aux frontières.

Le module historique `BezgelorCore.Telegraph` n'est pas réutilisé comme preuve
de fidélité : ses helpers utilisent le signe positif de sinus pour Z, un angle
conventionnel différent, une distance 3D dans le cône et une tolérance angulaire
sans intersection effective du rayon avec le bord. Il reste inchangé pour
préserver la démonstration existante. Les diagnostics corrigés s'en isolent.

NexusForever calcule le rayon dans `UnitEntity.InitialiseHitRadius` à partir de
`Creature2ModelInfo.HitRadius * CreatureEntry.ModelScale`, avec un défaut propre
au projet. `BezgelorCore.Entity` ne porte pas ce rayon authentique. Le protocole
de mouvement transmet bien position et rotation et `World.Instance` tient une
grille spatiale ; cela suffit à obtenir des candidats spatiaux, pas à valider
les collisions, la visibilité client, la faction ou la ligne de vue. Aucune
recherche circulaire n'est utilisée en remplacement du ciblage réel.

## Audit historique et corrections ciblées

`tools/tbl_extractor/tbl_extractor.py` omettait quatre octets après certains
champs texte, décalant les colonnes suivantes. Le correctif reprend la règle
du lecteur déjà livré en Elixir : premier offset texte nul, suivi d'un scalaire.
Les flottants ne sont plus arrondis à six décimales ; les types inconnus sont
refusés au lieu de sauter arbitrairement quatre octets. Le commentaire de taille
d'en-tête est corrigé de 104 à 96 octets ; son format binaire reste identique.

Le lecteur Python corrigé concorde intégralement avec le lecteur C# original
pour les vingt tables Spell4 étudiées, puis `Class` et `ItemDisplay` :
346 423 lignes, zéro divergence. Cette comparaison est une extraction de
données sur l'hôte ; aucun test Python n'est prétendu exécuté dans le conteneur.

Le scan binaire des 384 tables disponibles trouve 78 schémas texte/scalaires,
dont 56 contiennent effectivement ce rembourrage. Aucun échec de scan.
Quatre ont des JSON historiques correspondants dans le répertoire étudié :

| Table | Lignes JSON comparées | Lignes avec différences structurelles |
|---|---:|---:|
| Class | 6 | 6 |
| ItemDisplay | 8737 | 8737 |
| Spell4, sept parties | 66383 | 66383 |
| Spell4Base, deux parties | 44838 | 42316 |

Les différences d'arrondi seules sont comptées séparément. Exemple vérifiable :
`Class[1].localizedTextId` vaut 0 dans le JSON historique et 72 dans le TBL ;
`ItemDisplay[1].item2TypeId` vaut 0 au lieu de 51. L'audit donne les champs,
valeurs, premiers emplacements binaires et SHA256 correspondants.

**Aucun JSON historique ni catalogue de combat existant n'est régénéré.**
Les corriger change des données consommées au-delà de Quick Draw ; cela
nécessite la revue des consommateurs et des différences complètes, suivie
de tests ciblés. `source-7` conserve ce travail ouvert, avec les tables et
comptages désormais établis. Les 48 surcharges corrigées existantes restent
inchangées ; les autres sorts chargés par l'ancien catalogue ne sont pas déclarés fiables.

## Code, tests et limites de validation

Modules ajoutés : `BezgelorCore.Spell4PhasePlan`, `Spell4EventLedger`,
`Spell4TelegraphGeometry`. `BezgelorWorld.Spell4Diagnostics` expose le plan
et le périmètre géométrique diagnostique ; son blocage d'exécution est conservé.
Le module de diagnostic existant est bien dans **BezgelorWorld**, et non Core.
`Spell4Catalog`, `Spell4Chain`, `Spell4BaseDamage` et les garde-fous existants
sont réutilisés sans modifier leurs règles de combat.

**Compilation stricte réussie**, puis **169 tests ciblés, zéro échec** :
67 core, 7 data, 23 protocol, 72 world. Les 19 fichiers comprennent les 17
fichiers de la précédente campagne de 158 tests ; onze régressions sont ajoutées.

Les nouveaux tests couvrent ordre et conservation des masques/références,
refus d'une chronologie non vérifiée, idempotence par occurrence, événements
obsolètes, annulation, fin, limite mémoire, géométrie sur coordonnées connues,
frontières, distances, offsets, données invalides et refus de la sélection.
Une régression d'intégration charge le vrai Quick Draw, ses phases et ses
télégraphes puis vérifie que PV et XP restent inchangés. Les tests existants de
cibles valides/invalides, portée, annulation réelle de cast, mort, XP persistée,
cycles de proxies et combat de démonstration passent de nouveau.

Environnement unique des tests : `bezgelor-gameplay-test`, PostgreSQL
`bezgelor-gameplay-test-db:5432`, base `bezgelor_test`. Mot de passe transmis
depuis l'environnement du seul PostgreSQL de test, sans affichage.

`mix precommit` a été exécuté et reste en échec sur **43 fichiers préexistants
non formatés**, suivi `source-3`. Son étape de tests n'est pas atteinte.
Le contrôle de formatage des huit fichiers Elixir modifiés et `git diff --check`
réussissent. Aucun formatage global n'a été effectué. Les preuves de phase
régénérées sont identiques octet pour octet.

Aucune validation de combat en jeu n'a été effectuée. Aucun service n'est
redémarré, arrêté ou déployé. Aucun compte, personnage, fichier ou base de
production n'est modifié. Le contenu des TBL lus et des sources de référence
est contrôlé par empreinte, les originaux restant exclusivement des entrées.

## Dépendance bloquante suivante

Il faut obtenir une définition vérifiable du **producteur d'événements Spell4**
reliant les domaines de masques de `SpellPhase` et `Spell4Effects`, l'origine
temporelle de `phaseDelay`, les impulsions du canal et les conditions de proxy
ou d'interruption. Une implémentation documentée ou une capture du client et
du protocole de la même version, corrélée aux identifiants d'effets et aux
événements, doit permettre de déterminer quelles occurrences sont autorisées.

Ensuite restent à établir les rayons authentiques et leur échelle, la politique
de sélection 1, factions/conditions/visibilité/LoS, puis le pipeline final de
statistiques et dégâts décrit dans le
[rapport précédent](2026-10-20-spell4-authentic-combat.md).
La présence d'une arithmétique de dégâts de base diagnostique ne remplit pas
ces conditions. `source-nu9` conserve le blocage complet. Le travail borné de
reconstruction et de preuve est suivi par `source-8`.
