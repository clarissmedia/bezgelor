Formules Spell4 : provenance, implémentation et inconnues

Il faut distinguer trois niveaux de preuve : **T**, valeur relue dans une table originale avec empreinte ; **N**, formule ou correspondance présente dans une implémentation NexusForever identifiée ; **J**, comparaison indépendante avec des résultats du jeu original. Cette session apporte T et N. Elle n'apporte aucune preuve J.

Les chemins amont ci-dessous sont relatifs à `Source/` au commit `f9bb26efddbf304003fc8ebf484ac75bc6be84da`. [Manifest des liens et empreintes](2026-10-20-spell4-sources.json). L'installation locale NexusForever est une référence distincte, plus ancienne, dont le gestionnaire de dégâts contient encore `1337`.

**Données physiques et codes**

| Table / symbole | Champs et preuve | Niveau |
| --- | --- | --- |
| Spell4Effects / `Spell4EffectsEntry` | 42 champs, 168 octets : ID, spellId, cible, type, école, délais/ticks/durée, flags, dix DataBits, coûts par tick, conditions, menace, groupe, quatre types et valeurs de paramètres, phaseFlags, orderIndex | T + N, structure confirmée |
| SpellEffectType / `SpellEffectTypeEntry` | 150 lignes, 12 champs : ID, flags, dix dataType. Ces descripteurs ne contiennent pas à eux seuls une équation de dégâts. | T + N |
| GameFormula / `GameFormulaEntry` | 1217 lignes, 11 champs : ID, cinq uint32 dataint, cinq float32 datafloat. Paramètres sans expression exécutable ; leur rôle dépend du code qui référence chaque ID. | T + N |
| `SpellEffectParameterType` | 0 None ; 1–5 attributs ; 6 Weapon ; 7/8 PV max cible/lanceur ; 9 WeaponDPS ; 10 PerLevel ; 11 Grit ; 12 AssaultPower ; 13 SupportPower ; 14–17 boucliers ; 18 ItemBudget ; 19–26 PV/boucliers actuels/manquants et variantes | N ; tous les codes ne sont pas implémentés |
| `SpellEffectType` | Codes observés : 1 VitalModifier, 3 ForcedMove, 4 CCStateSet, 8 Damage, 10 Heal, 11 UnitPropertyModifier, 17 Fluff, 26 Proxy, 73 ModifySpellCooldown, 80 SpellForceRemove | N, confirmés dans l'énumération ; libellé ≠ support d'exécution |
| `SpellEffectTargetFlags` | Caster 1, Target 2, Telegraph 4 ; 8 demeure nommé inconnu | N ; pas une politique de faction ou de sélection |

La règle d'alignement texte et l'absence d'arrondi décimal intermédiaire sont indispensables. Les sept fichiers Spell4 historiques ne constituent pas une preuve correcte des valeurs de colonnes après un texte décalé. Le nouveau catalogue est une extraction ciblée, pas un remplacement global des données.

**Équation de base implémentée en diagnostic**

Source : [DamageCalculator.cs](https://github.com/NexusForever/NexusForever/blob/f9bb26efddbf304003fc8ebf484ac75bc6be84da/Source/NexusForever.Game/Combat/DamageCalculator.cs), symboles `CalculateBaseDamage`, `CalculateBasePropertyDamage`, `CalculateBaseEntityDamage`. Opérations élémentaires arrondies en float32 :

```text
P = somme(property_operand[i] × ParameterValue[i])
R = ceil(P) si P >= 0, sinon floor(P)
E = somme(entity_operand[i] × ParameterValue[i])
B = R + (DataBits01 + E) × float32_bits(DataBits00)
RawDamage = trunc_uint32(Property[140 + DamageType] × B)
```

La multiplication par DataBits00 ne porte pas sur R. GameFormula **1266** donne `datafloat0 = 0.25` pour AssaultRating, `datafloat01 = 0.25` pour SupportRating. Paramètre 12 : Property **35** × datafloat0 ; 13 : Property **36** × datafloat01. Paramètre 10 : niveau du lanceur. Multiplicateurs d'école : Property **141/142/143** pour Physical/Tech/Magic. Valeurs et correspondances sont documentées, sans certification J.

Le code exige les opérandes ; il ne reprend pas le défaut zéro du getter amont. Weapon, WeaponDPS, ItemBudget et les variantes de bouclier 20/24 sont refusés. Le traitement ItemBudget amont est ambigu ; aucun correctif supposé n'a été inventé. Les NPC et soins sont également refusés par cette API de dégâts de base. Un succès conserve `final_damage_verified: false`.

Les valeurs vitales sont des uint32 dans `Game.Abstract/Entity/IWorldEntity.cs`. Pour les PV ou boucliers manquants, leur soustraction entière précède la conversion float32. Les états structurellement incohérents sont refusés au lieu de reproduire un débordement entier.

Pour Quick Draw, les deux effets 99526/99528 portent exactement `ParameterValue00 = 0.10289999842643738` en float32, type 12, et `ParameterValue01 = 5.5`, type 10. Avec les propriétés de test explicites AssaultRating 400, niveau 50, multiplicateur physique 1, le résultat de référence est 286 **de base**. Cette valeur n'est ni le dégât d'un personnage réel ni une formule complète du jeu.

Les autres vecteurs couvrent les six classes : effets 177056 → 385, 177438 → 710, 62159 → 934, 83788 → 220, 79090 → 588, 141368 → 223, sous le même contexte synthétique et le multiplicateur d'école 1. Pour Shred, float32 produit un terme de niveau de `210.99998474121094` ; la troncature donne 220, sans réarrondi inventé vers 221. Les dix-neuf résultats de base et les opérandes synthétiques figurent dans la matrice JSON.

**Étages inspectés, non activés**

| Sujet | Source précise | Constat / décision | Confiance |
| --- | --- | --- | --- |
| Statistiques et équipement | `NexusForever.Game/Entity/ItemInfo.cs::CalculatePrimary`, GameFormula 549/1288 et 1265 ; `Game.Static/Entity/Property.cs` | Agrégation équipement/propriétés non raccordée dans Bezgelor. Les constantes et multiplications par classe de CharacterStats sont des démonstrations, y compris des identifiants de classe historiques incompatibles. Aucun alias power→AssaultRating n'est permis. | N partiel ; autorité des stats du projet non établie |
| Variance | `DamageCalculator.CalculateBaseDamageVariance` | Le code tirait 95..102 puis tronquait. Ne pas convertir cela en variance supposée ±5 %. Non porté. | N, J absent |
| Armure | `GetDamageAfterArmorMitigation`, GameFormula 1234 | La table donne un plafond 75 ; le code inclut niveau et armure. Il utilise l'offset nommé Magic aussi pour Physical, alors que Property 144 existe pour Physical. Incohérence à résoudre ; aucune substitution silencieuse. | N incomplet, pas J |
| Ratings de touche | `GetRatingPercentMod`, `CalculateDeflect` ; GameFormula 1230/1235 | Le code documente des conversions rating/niveau avec plafond, mais garde un TODO sur Strikethrough. Non porté. | N partiel |
| Critiques | `CalculateCrit`, `GetBasePercentMod` ; GameFormula 1231/1232/1236 | Sévérité de base, mitigation critique et déflexion critique restent partiellement non résolues. Le défaut critique des démonstrations n'est pas une solution. | N partiel |
| Glance | `CalculateGlance` ; GameFormula 1245/1271 | Proc et résultat réseau ne sont pas suffisamment certifiés. Non porté. | N partiel |
| Boucliers | `CalculateShieldAmount`, Property 175 | Calcul élémentaire documenté ; toutes les interactions et l'état autoritatif ne le sont pas dans Bezgelor. Non raccordé. | N partiel |
| Arrondi final | `Math.Round` et conversions uint32 dans DamageCalculator | L'ordre d'application et les arrondis de chaque étage comptent. Seul le sous-calcul de base décrit ci-dessus est reproduit. | N pour le sous-calcul, pas J |
| Soins | `SpellEffectType.Heal`, effets 78168/78280/78282/141384 | Des coefficients SupportPower/PerLevel existent. La mention Heal dans le switch de base n'établit pas tout le pipeline de soins ; aucun handler de soins équivalent n'a été trouvé dans SpellEffectHandler inspecté. | T + N partiels |
| Phases et événements | SpellPhase, DelayTime/TickTime/DurationTime, seuils et cast events ; `Spell.ExecuteEffects` | Champs conservés. Pas de moteur complet justifiant les phases, prérequis, ticks ou procs. Aucune exécution par aplatissement du graphe. | T ; sémantique d'exécution insuffisante |
| Groupes et modifications | Spell4EffectGroupList ; Spell4EffectModification | Groupes non nuls conservés, notamment listes 4/5/7. Aucune des 417 lignes de modification ne référence directement un des 81 IDs d'effet sélectionnés ; cela n'exclut pas d'autres mécanismes de modification. Aucun modificateur de groupe supposé n'est appliqué. | T, application non établie |
| Géométrie | `Spell/Telegraph.cs::InsideTelegraph`, `IsHitInsideAngle`, `Map/Search/SearchCheckTelegraph.cs` ; TelegraphDamage 3693/3694, contraintes 405 | Formes et données confirmées, implémentation amont partielle avec approximations/TODO. Politique de cibles, collisions et fidélité client non démontrées ; diagnostics seulement. | T + N partiels |
| Ressources | Coûts Spell4/Spell4Effects/Thresholds, prérequis 20117 ; `Game.Static/Entity/Vital.cs` | Champs conservés, aucune variation de ressource déduite du nom d'une compétence ou d'un runner. | T, exécution inconnue |

La [proposition amont sur Armor Pierce](https://github.com/NexusForever/NexusForever/pull/557) était encore ouverte lors de l'inspection et explicite une hypothèse sur le traitement de l'armure. Elle n'est pas utilisée comme formule certifiée. Le [suivi Spell Rework](https://github.com/NexusForever/NexusForever/issues/475) confirme aussi que le chantier est distinct de la présence de tables. Aucune modification des installations locales n'a été nécessaire pour inspecter ces sources.

Les informations manquantes pour une activation sont donc précisément : propriétés réelles agrégées et fiables ; phases/événements réellement déclenchés ; prérequis et ressources ; sélection des cibles et collisions ; pipeline final de touche/mitigation/critique/bouclier/soin ; contrat réseau et comparaison indépendante avec le jeu. L'équation de base n'est plus introuvable, mais elle ne suffit pas à satisfaire ces exigences.
