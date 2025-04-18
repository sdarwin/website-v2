import os

from django.contrib.auth import get_user_model
from django import forms

from allauth.account.forms import ResetPasswordKeyForm

from .models import Preferences
from news.models import NEWS_MODELS
from news.acl import can_approve


User = get_user_model()

NEWS_ENTRY_CHOICES = [(m.news_type, m._meta.verbose_name.title()) for m in NEWS_MODELS]


class CustomResetPasswordFromKeyForm(ResetPasswordKeyForm):
    def save(self, **kwargs):
        """Override default reset password form so we can mark unclaimed
        users as claimed once they have reset their passwords."""
        result = super().save(**kwargs)
        self.user.claim()
        return result


class PreferencesForm(forms.ModelForm):
    allow_notification_own_news_approved = forms.MultipleChoiceField(
        choices=NEWS_ENTRY_CHOICES,
        widget=forms.widgets.CheckboxSelectMultiple,
        label="Your own news is approved after moderation",
        required=False,
    )
    allow_notification_others_news_posted = forms.MultipleChoiceField(
        choices=NEWS_ENTRY_CHOICES,
        widget=forms.widgets.CheckboxSelectMultiple,
        label="Other users publish their news",
        required=False,
    )
    allow_notification_others_news_needs_moderation = forms.MultipleChoiceField(
        choices=NEWS_ENTRY_CHOICES,
        widget=forms.widgets.CheckboxSelectMultiple,
        label="There are new entries pending moderation",
        required=False,
    )
    allow_notification_terms_changed = forms.BooleanField(
        label="The site's Terms of Use or Privacy Policy are changed",
        required=False,
    )

    def __init__(self, *args, instance=None, **kwargs):
        if instance is not None:
            is_moderator = can_approve(instance.user)
            initial = kwargs.pop("initial", {})
            for field in self.Meta.fields:
                initial[field] = getattr(instance, field)
            kwargs["initial"] = initial
        else:
            is_moderator = False
            all_news = Preferences.ALL_NEWS_TYPES
            kwargs["initial"] = {i: all_news for i in self.Meta.fields}
            # Use default for terms changed field
            kwargs["initial"][
                "allow_notification_terms_changed"
            ] = Preferences().allow_notification_terms_changed

        super().__init__(*args, instance=instance, **kwargs)

        if not is_moderator:
            self.fields.pop("allow_notification_others_news_needs_moderation")
            self.initial.pop("allow_notification_others_news_needs_moderation")

    def save(self, *args, **kwargs):
        for field, value in self.cleaned_data.items():
            setattr(self.instance, field, value)
        return super().save(*args, **kwargs)

    class Meta:
        model = Preferences
        fields = [
            "allow_notification_own_news_approved",
            "allow_notification_others_news_posted",
            "allow_notification_others_news_needs_moderation",
            "allow_notification_terms_changed",
        ]


class UserProfileForm(forms.ModelForm):
    class Meta:
        model = User
        fields = [
            "email",
            "display_name",
            "indicate_last_login_method",
            "is_commit_author_name_overridden",
        ]
        labels = {
            "display_name": "Username",
            "is_commit_author_name_overridden": "Override commit author name",
        }
        override_msg = (
            "Globally replaces your git commit author name with Username "
            "value set above."
        )
        help_texts = {
            "display_name": "Your name as it will be displayed across the site.",
            "is_commit_author_name_overridden": override_msg,
        }


class CustomClearableFileInput(forms.ClearableFileInput):
    """
    Overrides the template for clearable file input so that we can display
    the widget without the filename/path displayed and change the checkbox
    to clear the field.
    """

    template_name = "users/clearable_file_input.html"


class UserProfilePhotoForm(forms.ModelForm):
    image = forms.FileField(widget=CustomClearableFileInput, required=False)

    class Meta:
        model = User
        fields = ["image"]

    def clean(self):
        """Ensure a user can't update their photo if they
        don't have permission."""
        cleaned_data = super().clean()
        if not self.instance.can_update_image:
            raise forms.ValidationError(
                "You do not have permission to update your profile photo."
            )
        return cleaned_data

    def save(self, commit=True):
        # Temporarily store the old image
        old_image = self.instance.image
        # Save the new image
        user = super().save(commit=False)

        if old_image:
            # Delete the old image file if there's a new image being uploaded
            if self.cleaned_data["image"] != old_image:
                old_image.delete(save=False)

        if self.cleaned_data.get("image"):
            new_image = self.cleaned_data["image"]
            _, file_extension = os.path.splitext(new_image.name)

            # Strip the leading period from the file extension.
            file_extension = file_extension.lstrip(".")

            new_image.name = f"{user.profile_image_filename_root}.{file_extension}"
            user.image = new_image

        if commit:
            user.save()

        return user


class DeleteAccountForm(forms.Form):
    verify = forms.CharField(help_text='To verify, type "delete my account" above.')

    def clean_verify(self):
        verify = self.cleaned_data["verify"]
        if self.cleaned_data["verify"] != "delete my account":
            raise forms.ValidationError('Please enter "delete my account"')
        return verify
