# Generated by Django 4.2.16 on 2025-02-07 19:37

from django.db import migrations, models


class Migration(migrations.Migration):

    dependencies = [
        ("libraries", "0027_libraryversion_dependencies"),
    ]

    operations = [
        migrations.CreateModel(
            name="WordcloudMergeWord",
            fields=[
                (
                    "id",
                    models.BigAutoField(
                        auto_created=True,
                        primary_key=True,
                        serialize=False,
                        verbose_name="ID",
                    ),
                ),
                ("from_word", models.CharField(max_length=255)),
                ("to_word", models.CharField(max_length=255)),
            ],
        ),
    ]
