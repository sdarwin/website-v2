import pytest

from django.contrib.auth import get_user_model
from django.core.files.uploadedfile import SimpleUploadedFile
from django.core.exceptions import ValidationError
from pytest_django.asserts import assertQuerySetEqual

from ..models import Preferences

User = get_user_model()


def test_regular_user(user):
    assert user.is_active is True
    assert user.is_staff is False
    assert user.is_superuser is False


def test_staff_user(staff_user):
    assert staff_user.is_active is True
    assert staff_user.is_staff is True
    assert staff_user.is_superuser is False


def test_super_user(super_user):
    assert super_user.is_active is True
    assert super_user.is_staff is True
    assert super_user.is_superuser is True


def test_profile_image_filename_root(user):
    assert user.profile_image_filename_root == f"profile-{user.id}"


def test_user_model_image_validator(user):
    """
    Test that the `image` field on the User model only accepts certain file types.
    """
    # Valid image file
    valid_image = SimpleUploadedFile(
        "test.jpg", b"file_content", content_type="image/jpeg"
    )
    user.image = valid_image
    # This should not raise any errors
    user.full_clean()

    # Invalid image file
    invalid_image = SimpleUploadedFile(
        "test.pdf", b"file_content", content_type="application/pdf"
    )
    user.image = invalid_image
    # This should raise a ValidationError
    with pytest.raises(ValidationError):
        user.full_clean()


def test_user_model_image_file_size(user):
    """
    Test that the `image` field rejects files larger than a specific size.
    """
    valid_image = SimpleUploadedFile(
        "test.jpg", b"a" * (1 * 1024 * 1024 - 1), content_type="image/jpeg"
    )
    user.image = valid_image
    # This should not raise any errors
    user.full_clean()

    # This should fail (just over 1MB)
    invalid_image = SimpleUploadedFile(
        "too_large.jpg", b"a" * (1 * 1024 * 1024 + 1), content_type="image/jpeg"
    )
    user.image = invalid_image
    # This should raise a ValidationError for file size
    with pytest.raises(ValidationError):
        user.full_clean()


def test_claim(user):
    user.claimed = False
    user.save()
    user.refresh_from_db()

    assert not user.claimed
    user.claim()
    user.refresh_from_db()
    assert user.claimed


def test_find_contributor_by_email(user):
    found_user = User.objects.find_contributor(email=user.email)
    assert found_user == user


def test_find_contributor_by_email_not_found():
    non_existent_email = "nonexistent@email.com"
    found_user = User.objects.find_contributor(email=non_existent_email)
    assert found_user is None


def test_find_contributor_not_author_or_maintainer(user: User):
    found_user = User.objects.find_contributor(display_name=user.display_name)
    assert found_user is None


def test_find_contributor_by_display_name_not_found():
    non_existent_name = "Nonexistent User"
    found_user = User.objects.find_contributor(display_name=non_existent_name)
    assert found_user is None


def test_find_contributor_by_display_name_multiple_results(user, staff_user):
    staff_user.display_name = user.display_name
    staff_user.save()

    found_user = User.objects.find_contributor(display_name=user.display_name)
    assert found_user is None


def test_find_contributor_no_args():
    found_user = User.objects.find_contributor()
    assert found_user is None


def test_find_contributor_is_author(user, library):
    library.authors.add(user)
    library.save()

    found_user = User.objects.find_contributor(display_name=user.display_name)
    assert found_user == user


def test_find_contributor_is_maintainer(user, library_version):
    library_version.maintainers.add(user)
    library_version.save()

    found_user = User.objects.find_contributor(display_name=user.display_name)
    assert found_user == user


def test_preferences(user):
    assert Preferences.objects.get(user=user) == user.preferences
    assert user.preferences.notifications == {
        "own-news-approved": [Preferences.NEWS_TYPES_WILDCARD],
        "others-news-posted": [],
        "others-news-needs-moderation": [Preferences.NEWS_TYPES_WILDCARD],
        "terms-changed": [False],
    }


def test_preferences_set_value_terms(user):
    notification_type = "terms-changed"
    attr_name = f"allow_notification_{notification_type.replace('-', '_')}"

    assert user.preferences.notifications[notification_type] == [False]
    assert getattr(user.preferences, attr_name) is False

    # Opt in
    setattr(user.preferences, attr_name, True)
    assert user.preferences.notifications[notification_type] == [True]
    assert getattr(user.preferences, attr_name) is True


@pytest.mark.parametrize(
    "notification_type, default",
    [
        ("own-news-approved", [Preferences.NEWS_TYPES_WILDCARD]),
        ("others-news-posted", []),
        ("others-news-needs-moderation", [Preferences.NEWS_TYPES_WILDCARD]),
    ],
)
def test_preferences_set_value(user, notification_type, default):
    attr_name = f"allow_notification_{notification_type.replace('-', '_')}"

    # default value
    assert user.preferences.notifications[notification_type] == default
    assert getattr(user.preferences, attr_name) == (
        Preferences.ALL_NEWS_TYPES
        if Preferences.NEWS_TYPES_WILDCARD in default
        else default
    )

    # set empty list
    setattr(user.preferences, attr_name, [])
    assert getattr(user.preferences, attr_name) == []
    assert user.preferences.notifications[notification_type] == []

    # set a few values
    setattr(user.preferences, attr_name, ["link", "blogpost"])
    assert getattr(user.preferences, attr_name) == ["blogpost", "link"]
    assert user.preferences.notifications[notification_type] == ["blogpost", "link"]

    # set all values
    setattr(user.preferences, attr_name, list(reversed(Preferences.ALL_NEWS_TYPES)))
    assert getattr(user.preferences, attr_name) == Preferences.ALL_NEWS_TYPES
    assert user.preferences.notifications[notification_type] == [
        Preferences.NEWS_TYPES_WILDCARD
    ]


@pytest.mark.parametrize("news_type", Preferences.ALL_NEWS_TYPES)
def test_manager_preferences_shortcuts(tp, make_user, news_type):
    # user does not allow notifications
    make_user(email="u1@example.com", allow_notification_others_news_posted=[])
    # allows nofitications for all news type
    u2 = make_user(
        email="u2@example.com",
        allow_notification_others_news_posted=[Preferences.NEWS_TYPES_WILDCARD],
    )
    # allows only for the same type as entry
    u3 = make_user(
        email="u3@example.com", allow_notification_others_news_posted=[news_type]
    )
    # allows for any other type except entry's
    make_user(
        email="u4@example.com",
        allow_notification_others_news_posted=[
            t for t in Preferences.ALL_NEWS_TYPES if t != news_type
        ],
    )

    with tp.assertNumQueriesLessThan(2, verbose=True):
        result = User.objects.allow_notification_others_news_posted(news_type)

    assertQuerySetEqual(result, [u2, u3], ordered=False)
